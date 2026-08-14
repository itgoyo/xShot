APP_NAME = xShot
BUNDLE_ID = com.itgoyo.xShot
SRC_DIR = xShot
BUILD_DIR = build
DIST_DIR = dist
APP = $(DIST_DIR)/$(APP_NAME).app
ICON = $(SRC_DIR)/Resources/AppIcon.icns
WALLPAPERS = $(wildcard $(SRC_DIR)/Resources/Wallpapers/*.jpg)
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $(SRC_DIR)/Info.plist 2>/dev/null)

CC = clang
CFLAGS = -fobjc-arc -fobjc-weak -mmacosx-version-min=13.0 -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations -O2
FRAMEWORKS = \
	-framework Cocoa \
	-framework Carbon \
	-framework CoreGraphics \
	-framework CoreImage \
	-framework CoreText \
	-framework Vision \
	-framework ApplicationServices \
	-framework UniformTypeIdentifiers \
	-framework QuartzCore \
	-framework ServiceManagement

SRCS = $(wildcard $(SRC_DIR)/*.m)
OBJS = $(patsubst $(SRC_DIR)/%.m,$(BUILD_DIR)/%.o,$(SRCS))

.PHONY: all clean run dmg version icon

all: $(APP)

icon:
	@chmod +x scripts/generate-app-icon.sh
	@./scripts/generate-app-icon.sh

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.m
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(SRC_DIR) -c $< -o $@

$(BUILD_DIR)/$(APP_NAME): $(OBJS)
	$(CC) $(CFLAGS) $(FRAMEWORKS) $^ -o $@

$(APP): $(BUILD_DIR)/$(APP_NAME) $(SRC_DIR)/Info.plist $(ICON) $(WALLPAPERS)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources/Wallpapers
	cp $(SRC_DIR)/Info.plist $(APP)/Contents/Info.plist
	cp $(BUILD_DIR)/$(APP_NAME) $(APP)/Contents/MacOS/$(APP_NAME)
	cp $(ICON) $(APP)/Contents/Resources/AppIcon.icns
	@if [ -n "$(WALLPAPERS)" ]; then cp $(WALLPAPERS) $(APP)/Contents/Resources/Wallpapers/; fi
	codesign --force --deep --sign - $(APP)
	@echo "Built $(APP) ($(VERSION))"

run: $(APP)
	open $(APP)

# make version V=1.2.0
version:
	@test -n "$(V)" || (echo "Usage: make version V=1.2.0" >&2; exit 1)
	@chmod +x scripts/set-version.sh
	@./scripts/set-version.sh "$(V)"

dmg: $(APP)
	@chmod +x scripts/create-dmg.sh
	@./scripts/create-dmg.sh

clean:
	rm -rf $(BUILD_DIR) $(DIST_DIR)
