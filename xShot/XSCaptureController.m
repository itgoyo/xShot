#import "XSCaptureController.h"
#import "XSEditorWindowController.h"
#import "XSAnnotationWindowController.h"
#import "XSPinController.h"
#import <CoreGraphics/CoreGraphics.h>

@interface XSOverlayView : NSView
@property (nonatomic, strong) NSImage *screenImage;
@property (nonatomic, assign) NSRect selection;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, assign) BOOL windowMode;
@property (nonatomic, assign) NSRect highlightedWindow;
@property (nonatomic, weak) NSScreen *hostScreen;
@property (nonatomic, assign) BOOL confirmToCapture;
@property (nonatomic, copy) void (^onComplete)(NSImage * _Nullable cropped, NSRect screenRect);
@property (nonatomic, copy) void (^onCancel)(void);
@end

@interface XSOverlayWindow : NSPanel
@property (nonatomic, strong) XSOverlayView *overlayView;
@end

@implementation XSOverlayWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end

typedef NS_ENUM(NSInteger, XSSelHandle) {
    XSSelHandleNone = 0,
    XSSelHandleMove,
    XSSelHandleTL, XSSelHandleT, XSSelHandleTR,
    XSSelHandleL,                 XSSelHandleR,
    XSSelHandleBL, XSSelHandleB, XSSelHandleBR,
};

@implementation XSOverlayView {
    NSPoint _start;
    NSTrackingArea *_track;
    BOOL _adjusting;
    XSSelHandle _handle;
    NSRect _selAtDrag;
    NSButton *_confirmBtn;
}

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isFlipped { return NO; }

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_track) [self removeTrackingArea:_track];
    _track = [[NSTrackingArea alloc] initWithRect:self.bounds
                                          options:NSTrackingMouseMoved | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                            owner:self userInfo:nil];
    [self addTrackingArea:_track];
}

- (void)drawRect:(NSRect)dirty {
    [self.screenImage drawInRect:self.bounds fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1];
    [[[NSColor blackColor] colorWithAlphaComponent:0.38] setFill];
    NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);

    NSRect hole = NSZeroRect;
    if (self.windowMode && self.highlightedWindow.size.width > 2) {
        hole = self.highlightedWindow;
    } else if (self.selection.size.width > 2 && self.selection.size.height > 2) {
        hole = self.selection;
    }
    if (hole.size.width > 2) {
        [self.screenImage drawInRect:hole fromRect:[self imageRectForViewRect:hole] operation:NSCompositingOperationCopy fraction:1];
        [[NSColor colorWithWhite:1 alpha:0.95] setStroke];
        NSBezierPath *inner = [NSBezierPath bezierPathWithRect:NSInsetRect(hole, 0.5, 0.5)];
        inner.lineWidth = 1;
        [inner stroke];

        NSInteger w = (NSInteger)llround(hole.size.width);
        NSInteger h = (NSInteger)llround(hole.size.height);
        NSString *label = [NSString stringWithFormat:@"%ld × %ld", (long)w, (long)h];
        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: NSColor.whiteColor
        };
        NSSize ts = [label sizeWithAttributes:attrs];
        NSRect badge = NSMakeRect(NSMaxX(hole) - ts.width - 14, NSMinY(hole) - ts.height - 14, ts.width + 12, ts.height + 8);
        if (badge.origin.y < 8) badge.origin.y = NSMaxY(hole) + 8;
        NSBezierPath *bp = [NSBezierPath bezierPathWithRoundedRect:badge xRadius:6 yRadius:6];
        [[[NSColor blackColor] colorWithAlphaComponent:0.72] setFill];
        [bp fill];
        [label drawAtPoint:NSMakePoint(badge.origin.x + 6, badge.origin.y + 4) withAttributes:attrs];

        if (_adjusting) {
            [[NSColor colorWithWhite:1 alpha:1] setFill];
            [[[NSColor blackColor] colorWithAlphaComponent:0.35] setStroke];
            for (NSValue *hv in [self handleRects]) {
                NSRect hr = hv.rectValue;
                NSBezierPath *hp = [NSBezierPath bezierPathWithRect:NSInsetRect(hr, 1, 1)];
                hp.lineWidth = 1;
                [hp fill];
                [hp stroke];
            }
        }
    }
}

- (NSRect)imageRectForViewRect:(NSRect)r {
    CGFloat sx = self.screenImage.size.width / self.bounds.size.width;
    CGFloat sy = self.screenImage.size.height / self.bounds.size.height;
    return NSMakeRect(r.origin.x * sx, r.origin.y * sy, r.size.width * sx, r.size.height * sy);
}

- (NSRect)screenRectForViewRect:(NSRect)r {
    NSRect sf = self.hostScreen.frame;
    return NSMakeRect(sf.origin.x + r.origin.x, sf.origin.y + r.origin.y, r.size.width, r.size.height);
}

- (NSArray<NSValue *> *)handleRects {
    NSRect s = self.selection;
    CGFloat z = 8;
    CGFloat mx = NSMidX(s), my = NSMidY(s);
    return @[
        [NSValue valueWithRect:NSMakeRect(NSMinX(s) - z/2, NSMaxY(s) - z/2, z, z)],
        [NSValue valueWithRect:NSMakeRect(mx - z/2, NSMaxY(s) - z/2, z, z)],
        [NSValue valueWithRect:NSMakeRect(NSMaxX(s) - z/2, NSMaxY(s) - z/2, z, z)],
        [NSValue valueWithRect:NSMakeRect(NSMinX(s) - z/2, my - z/2, z, z)],
        [NSValue valueWithRect:NSMakeRect(NSMaxX(s) - z/2, my - z/2, z, z)],
        [NSValue valueWithRect:NSMakeRect(NSMinX(s) - z/2, NSMinY(s) - z/2, z, z)],
        [NSValue valueWithRect:NSMakeRect(mx - z/2, NSMinY(s) - z/2, z, z)],
        [NSValue valueWithRect:NSMakeRect(NSMaxX(s) - z/2, NSMinY(s) - z/2, z, z)],
    ];
}

- (XSSelHandle)handleAtPoint:(NSPoint)p {
    if (!_adjusting || self.selection.size.width < 4) return XSSelHandleNone;
    NSRect s = self.selection;
    CGFloat hit = 10;
    NSRect tl = NSMakeRect(NSMinX(s) - hit, NSMaxY(s) - hit, hit * 2, hit * 2);
    NSRect tr = NSMakeRect(NSMaxX(s) - hit, NSMaxY(s) - hit, hit * 2, hit * 2);
    NSRect bl = NSMakeRect(NSMinX(s) - hit, NSMinY(s) - hit, hit * 2, hit * 2);
    NSRect br = NSMakeRect(NSMaxX(s) - hit, NSMinY(s) - hit, hit * 2, hit * 2);
    NSRect t  = NSMakeRect(NSMidX(s) - hit, NSMaxY(s) - hit, hit * 2, hit * 2);
    NSRect b  = NSMakeRect(NSMidX(s) - hit, NSMinY(s) - hit, hit * 2, hit * 2);
    NSRect l  = NSMakeRect(NSMinX(s) - hit, NSMidY(s) - hit, hit * 2, hit * 2);
    NSRect r  = NSMakeRect(NSMaxX(s) - hit, NSMidY(s) - hit, hit * 2, hit * 2);
    if (NSPointInRect(p, tl)) return XSSelHandleTL;
    if (NSPointInRect(p, tr)) return XSSelHandleTR;
    if (NSPointInRect(p, bl)) return XSSelHandleBL;
    if (NSPointInRect(p, br)) return XSSelHandleBR;
    if (NSPointInRect(p, t))  return XSSelHandleT;
    if (NSPointInRect(p, b))  return XSSelHandleB;
    if (NSPointInRect(p, l))  return XSSelHandleL;
    if (NSPointInRect(p, r))  return XSSelHandleR;
    if (NSPointInRect(p, s))  return XSSelHandleMove;
    return XSSelHandleNone;
}

- (void)applyCursorForHandle:(XSSelHandle)h {
    switch (h) {
        case XSSelHandleTL: case XSSelHandleBR: [[NSCursor resizeUpDownCursor] set]; break;
        case XSSelHandleTR: case XSSelHandleBL: [[NSCursor resizeUpDownCursor] set]; break;
        case XSSelHandleT:  case XSSelHandleB:  [[NSCursor resizeUpDownCursor] set]; break;
        case XSSelHandleL:  case XSSelHandleR:  [[NSCursor resizeLeftRightCursor] set]; break;
        case XSSelHandleMove: [[NSCursor openHandCursor] set]; break;
        default: [[NSCursor crosshairCursor] set]; break;
    }
}

- (NSRect)clampedSelection:(NSRect)s {
    NSRect b = self.bounds;
    if (s.size.width < 8) s.size.width = 8;
    if (s.size.height < 8) s.size.height = 8;
    if (s.origin.x < 0) s.origin.x = 0;
    if (s.origin.y < 0) s.origin.y = 0;
    if (NSMaxX(s) > NSMaxX(b)) s.origin.x = NSMaxX(b) - s.size.width;
    if (NSMaxY(s) > NSMaxY(b)) s.origin.y = NSMaxY(b) - s.size.height;
    return NSIntegralRect(s);
}

- (void)resizeSelectionToPoint:(NSPoint)p {
    NSRect s = _selAtDrag;
    CGFloat minX = NSMinX(s), maxX = NSMaxX(s), minY = NSMinY(s), maxY = NSMaxY(s);
    switch (_handle) {
        case XSSelHandleTL: minX = p.x; maxY = p.y; break;
        case XSSelHandleTR: maxX = p.x; maxY = p.y; break;
        case XSSelHandleBL: minX = p.x; minY = p.y; break;
        case XSSelHandleBR: maxX = p.x; minY = p.y; break;
        case XSSelHandleT:  maxY = p.y; break;
        case XSSelHandleB:  minY = p.y; break;
        case XSSelHandleL:  minX = p.x; break;
        case XSSelHandleR:  maxX = p.x; break;
        default: return;
    }
    self.selection = [self clampedSelection:NSMakeRect(MIN(minX, maxX), MIN(minY, maxY),
                                                       fabs(maxX - minX), fabs(maxY - minY))];
}

- (void)ensureConfirmButton {
    if (_confirmBtn) return;
    _confirmBtn = [NSButton buttonWithTitle:@"" target:self action:@selector(confirmSelection)];
    NSImage *img = [NSImage imageWithSize:NSMakeSize(32, 32) flipped:NO drawingHandler:^BOOL(NSRect r) {
        NSBezierPath *bg = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(r, 2, 2)];
        [[NSColor colorWithCalibratedRed:0.22 green:0.78 blue:0.40 alpha:1] setFill];
        [bg fill];
        NSBezierPath *ck = [NSBezierPath bezierPath];
        ck.lineWidth = 2.6;
        ck.lineCapStyle = NSLineCapStyleRound;
        ck.lineJoinStyle = NSLineJoinStyleRound;
        [ck moveToPoint:NSMakePoint(9, 16)];
        [ck lineToPoint:NSMakePoint(14, 11)];
        [ck lineToPoint:NSMakePoint(23, 21)];
        [[NSColor whiteColor] setStroke];
        [ck stroke];
        return YES;
    }];
    _confirmBtn.image = img;
    _confirmBtn.imagePosition = NSImageOnly;
    _confirmBtn.bordered = NO;
    _confirmBtn.hidden = YES;
    [self addSubview:_confirmBtn];
}

- (void)layoutConfirmButton {
    if (!_confirmBtn || _confirmBtn.hidden) return;
    NSRect s = self.selection;
    CGFloat bw = 36, bh = 36;
    CGFloat gap = 8;
    // 右下角：优先贴在选区右下外侧，空间不足时改到选区内部右下
    CGFloat x = round(NSMaxX(s) - bw + 6);
    CGFloat y = round(NSMinY(s) - bh - gap);
    if (y < gap) {
        y = round(NSMinY(s) + gap);
        x = round(NSMaxX(s) - bw - gap);
    }
    if (x + bw > NSMaxX(self.bounds) - gap) x = NSMaxX(self.bounds) - bw - gap;
    if (x < gap) x = gap;
    if (y + bh > NSMaxY(self.bounds) - gap) y = NSMaxY(self.bounds) - bh - gap;
    if (y < gap) y = gap;
    _confirmBtn.frame = NSMakeRect(x, y, bw, bh);
}

- (void)enterAdjusting {
    _adjusting = YES;
    [self ensureConfirmButton];
    _confirmBtn.hidden = NO;
    [self layoutConfirmButton];
    [self setNeedsDisplay:YES];
}

- (void)exitAdjusting {
    _adjusting = NO;
    _handle = XSSelHandleNone;
    _confirmBtn.hidden = YES;
}

- (void)mouseDown:(NSEvent *)event {
    if (self.windowMode) {
        [self confirmWindow];
        return;
    }
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (_adjusting) {
        XSSelHandle h = [self handleAtPoint:p];
        if (h != XSSelHandleNone) {
            _handle = h;
            _selAtDrag = self.selection;
            _start = p;
            self.dragging = YES;
            return;
        }
        [self exitAdjusting];
    }
    self.dragging = YES;
    _handle = XSSelHandleNone;
    _start = p;
    self.selection = NSMakeRect(_start.x, _start.y, 0, 0);
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.dragging) return;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (_handle == XSSelHandleMove) {
        NSRect s = _selAtDrag;
        s.origin.x += p.x - _start.x;
        s.origin.y += p.y - _start.y;
        self.selection = [self clampedSelection:s];
        [self layoutConfirmButton];
        [self setNeedsDisplay:YES];
        return;
    }
    if (_handle >= XSSelHandleTL) {
        [self resizeSelectionToPoint:p];
        [self layoutConfirmButton];
        [self setNeedsDisplay:YES];
        return;
    }
    self.selection = NSIntegralRect(NSMakeRect(MIN(_start.x, p.x), MIN(_start.y, p.y),
                                               fabs(p.x - _start.x), fabs(p.y - _start.y)));
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    if (!self.dragging) return;
    self.dragging = NO;
    BOOL wasResizeOrMove = (_handle != XSSelHandleNone);
    _handle = XSSelHandleNone;
    if (self.selection.size.width < 4 || self.selection.size.height < 4) {
        self.selection = NSZeroRect;
        [self exitAdjusting];
        [self setNeedsDisplay:YES];
        return;
    }
    if (self.confirmToCapture) {
        [self enterAdjusting];
        return;
    }
    if (!wasResizeOrMove) [self confirmSelection];
}

- (void)mouseMoved:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (self.windowMode) {
        [self highlightWindowAtPoint:p];
        return;
    }
    if (_adjusting) [self applyCursorForHandle:[self handleAtPoint:p]];
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 53) {
        if (self.onCancel) self.onCancel();
        return;
    }
    if (event.keyCode == 49) {
        self.windowMode = !self.windowMode;
        self.selection = NSZeroRect;
        [self exitAdjusting];
        [self setNeedsDisplay:YES];
        return;
    }
    if (event.keyCode == 36 && self.selection.size.width > 4) {
        [self confirmSelection];
    }
}

- (void)highlightWindowAtPoint:(NSPoint)p {
    NSArray *list = (__bridge_transfer NSArray *)CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    NSRect best = NSZeroRect;
    CGFloat bestArea = CGFLOAT_MAX;
    for (NSDictionary *info in list) {
        NSString *owner = info[(id)kCGWindowOwnerName];
        if ([owner isEqualToString:@"xShot"] || [owner isEqualToString:@"Window Server"]) continue;
        NSNumber *layer = info[(id)kCGWindowLayer];
        if (layer.intValue != 0) continue;
        CGRect b = CGRectZero;
        CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[(id)kCGWindowBounds], &b);
        NSRect cocoa = [self cgWindowRectToView:b];
        if (NSPointInRect(p, cocoa) && cocoa.size.width * cocoa.size.height < bestArea && cocoa.size.width > 40) {
            bestArea = cocoa.size.width * cocoa.size.height;
            best = cocoa;
        }
    }
    self.highlightedWindow = best;
    [self setNeedsDisplay:YES];
}

- (NSRect)cgWindowRectToView:(CGRect)cg {
    NSRect sf = self.hostScreen.frame;
    CGFloat x = cg.origin.x - sf.origin.x;
    CGFloat y = (sf.origin.y + sf.size.height) - (cg.origin.y + cg.size.height);
    return NSMakeRect(x, y, cg.size.width, cg.size.height);
}

- (void)confirmSelection {
    NSImage *cropped = [self cropViewRect:self.selection];
    if (self.onComplete) self.onComplete(cropped, [self screenRectForViewRect:self.selection]);
}

- (void)confirmWindow {
    if (self.highlightedWindow.size.width < 4) return;
    NSImage *cropped = [self cropViewRect:self.highlightedWindow];
    if (self.onComplete) self.onComplete(cropped, [self screenRectForViewRect:self.highlightedWindow]);
}

- (NSImage *)cropViewRect:(NSRect)r {
    NSRect ir = [self imageRectForViewRect:r];
    NSImage *out = [[NSImage alloc] initWithSize:ir.size];
    [out lockFocus];
    [self.screenImage drawInRect:NSMakeRect(0, 0, ir.size.width, ir.size.height)
                        fromRect:ir
                       operation:NSCompositingOperationCopy
                        fraction:1];
    [out unlockFocus];
    return out;
}

@end

typedef NS_ENUM(NSInteger, XSCaptureMode) {
    XSCaptureModeBeautify = 0,
    XSCaptureModeAnnotate,
    XSCaptureModePlain,
};

@implementation XSCaptureController {
    NSMutableArray<XSOverlayWindow *> *_windows;
    XSCaptureMode _mode;
}

+ (instancetype)shared {
    static XSCaptureController *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [XSCaptureController new]; });
    return c;
}

- (void)beginCapture {
    _mode = XSCaptureModeBeautify;
    [self start];
}

- (void)beginPlainCapture {
    _mode = XSCaptureModePlain;
    [self start];
}

- (void)beginAnnotateCapture {
    _mode = XSCaptureModeAnnotate;
    [self start];
}

- (void)start {
    if (_windows.count) [self dismiss];
    if (!CGPreflightScreenCaptureAccess()) {
        CGRequestScreenCaptureAccess();
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"需要屏幕录制权限";
        alert.informativeText = @"系统设置 → 隐私与安全性 → 屏幕录制，勾选 xShot，然后重试。";
        [alert runModal];
        return;
    }
    [NSApp hide:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self showOverlays];
    });
}

- (NSImage *)imageForScreen:(NSScreen *)screen {
    NSDictionary *desc = screen.deviceDescription;
    CGDirectDisplayID did = [desc[@"NSScreenNumber"] unsignedIntValue];
    CGImageRef cg = CGDisplayCreateImage(did);
    if (!cg) return nil;
    NSImage *img = [[NSImage alloc] initWithCGImage:cg size:screen.frame.size];
    CGImageRelease(cg);
    return img;
}

- (void)showOverlays {
    _windows = [NSMutableArray array];
    for (NSScreen *screen in NSScreen.screens) {
        NSImage *shot = [self imageForScreen:screen];
        if (!shot) continue;
        XSOverlayWindow *win = [[XSOverlayWindow alloc] initWithContentRect:screen.frame
                                                                 styleMask:NSWindowStyleMaskBorderless
                                                                   backing:NSBackingStoreBuffered
                                                                     defer:NO];
        win.level = NSScreenSaverWindowLevel;
        win.opaque = YES;
        win.backgroundColor = NSColor.blackColor;
        win.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
        win.releasedWhenClosed = NO;
        XSOverlayView *view = [[XSOverlayView alloc] initWithFrame:NSMakeRect(0, 0, screen.frame.size.width, screen.frame.size.height)];
        view.screenImage = shot;
        view.hostScreen = screen;
        view.confirmToCapture = (_mode == XSCaptureModePlain);
        __weak typeof(self) weakSelf = self;
        view.onComplete = ^(NSImage *cropped, NSRect screenRect) {
            [weakSelf finishWithImage:cropped screenRect:screenRect];
        };
        view.onCancel = ^{
            [weakSelf dismiss];
            [NSApp unhide:nil];
        };
        win.overlayView = view;
        win.contentView = view;
        [win setFrame:screen.frame display:YES];
        [win makeKeyAndOrderFront:nil];
        [_windows addObject:win];
    }
    [NSApp unhide:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [_windows.firstObject makeKeyAndOrderFront:nil];
    [_windows.firstObject makeFirstResponder:_windows.firstObject.overlayView];
    [[NSCursor crosshairCursor] set];
}

- (void)finishWithImage:(NSImage *)image screenRect:(NSRect)screenRect {
    XSCaptureMode mode = _mode;
    _mode = XSCaptureModeBeautify;
    [self dismiss];
    [NSApp unhide:nil];
    if (!image || image.size.width < 2) return;
    if (mode == XSCaptureModePlain) {
        NSPasteboard *pb = NSPasteboard.generalPasteboard;
        [pb clearContents];
        [pb writeObjects:@[image]];
        [[XSPinController shared] rememberPlainCaptureAtScreenRect:screenRect pasteboardChangeCount:pb.changeCount];
        [self showCopiedHUD];
        return;
    }
    [NSApp activateIgnoringOtherApps:YES];
    if (mode == XSCaptureModeAnnotate) {
        [[XSAnnotationWindowController shared] showWithImage:image];
        return;
    }
    [[XSEditorWindowController shared] showWithImage:image];
}

- (void)showCopiedHUD {
    NSPanel *hud = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 148, 48)
                                              styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                backing:NSBackingStoreBuffered defer:NO];
    hud.level = NSFloatingWindowLevel + 5;
    hud.opaque = NO;
    hud.backgroundColor = NSColor.clearColor;
    hud.hasShadow = YES;
    NSView *v = [[NSView alloc] initWithFrame:hud.contentView.bounds];
    v.wantsLayer = YES;
    v.layer.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.78].CGColor;
    v.layer.cornerRadius = 12;
    NSTextField *label = [NSTextField labelWithString:@"已复制到剪贴板"];
    label.textColor = NSColor.whiteColor;
    label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    label.alignment = NSTextAlignmentCenter;
    label.frame = NSMakeRect(0, 14, 148, 20);
    [v addSubview:label];
    hud.contentView = v;
    NSScreen *s = NSScreen.mainScreen;
    NSRect sf = s.visibleFrame;
    [hud setFrameOrigin:NSMakePoint(sf.origin.x + (sf.size.width - 148) / 2, sf.origin.y + 80)];
    [hud orderFront:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [hud close];
    });
}

- (void)dismiss {
    for (XSOverlayWindow *w in _windows) {
        w.overlayView.screenImage = nil;
        [w close];
    }
    [_windows removeAllObjects];
    [[NSCursor arrowCursor] set];
}

@end
