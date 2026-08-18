#!/bin/bash
# 从 AppIcon.source.png 生成 AppIcon.png / AppIcon.iconset / AppIcon.icns
# 圆角外透明：将四角连通的黑色/暗色区域转为 alpha=0，不填充任何背景色
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RES="$ROOT/xShot/Resources"
SRC="${1:-$RES/AppIcon.source.png}"
ICONSET="$RES/AppIcon.iconset"
MASTER="$RES/AppIcon.png"
ICNS="$RES/AppIcon.icns"

if [[ ! -f "$SRC" ]]; then
  echo "Source icon not found: $SRC" >&2
  exit 1
fi

mkdir -p "$ICONSET"
rm -f "$ICONSET"/*.png 2>/dev/null || true

python3 - "$SRC" "$MASTER" <<'PY'
import os
import sys
from collections import deque
from PIL import Image

src, out = sys.argv[1], sys.argv[2]
icon_scale = float(os.environ.get("ICON_SCALE", "0.82"))

im = Image.open(src).convert("RGBA")

w, h = im.size
side = min(w, h)
x0 = (w - side) // 2
y0 = (h - side) // 2
im = im.crop((x0, y0, x0 + side, y0 + side))
if side != 1024:
    im = im.resize((1024, 1024), Image.Resampling.LANCZOS)

w, h = im.size
px = im.load()

def lum(r, g, b):
    return (r + g + b) / 3.0

def is_outside(r, g, b, a):
    if a == 0:
        return True
    return lum(r, g, b) < 165

seen = bytearray(w * h)
q = deque()
for sx, sy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
    r, g, b, a = px[sx, sy]
    if is_outside(r, g, b, a):
        q.append((sx, sy))
        seen[sy * w + sx] = 1

while q:
    x, y = q.popleft()
    r, g, b, a = px[x, y]
    px[x, y] = (r, g, b, 0)
    for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
        if nx < 0 or ny < 0 or nx >= w or ny >= h:
            continue
        idx = ny * w + nx
        if seen[idx]:
            continue
        nr, ng, nb, na = px[nx, ny]
        if is_outside(nr, ng, nb, na):
            seen[idx] = 1
            q.append((nx, ny))

# macOS 启动台图标需留安全边距，避免视觉上比系统图标更大
target = max(1, int(round(1024 * icon_scale)))
im = im.resize((target, target), Image.Resampling.LANCZOS)
canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
offset = (1024 - target) // 2
canvas.paste(im, (offset, offset), im)
im = canvas

im.save(out, format="PNG")
alpha = im.split()[3].getextrema()
print(f"master {out} {im.size} scale={icon_scale} alpha={alpha}")
PY

gen() {
  local size=$1 name=$2
  sips -s format png -z "$size" "$size" "$MASTER" --out "$ICONSET/$name" >/dev/null
}

gen 16 icon_16x16.png
gen 32 icon_16x16@2x.png
gen 32 icon_32x32.png
gen 64 icon_32x32@2x.png
gen 128 icon_128x128.png
gen 256 icon_128x128@2x.png
gen 256 icon_256x256.png
gen 512 icon_256x256@2x.png
gen 512 icon_512x512.png
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$ICNS"
echo "Generated $ICNS"
