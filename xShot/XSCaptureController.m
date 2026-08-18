#import "XSCaptureController.h"
#import "XSEditorWindowController.h"
#import "XSPinController.h"
#import <CoreGraphics/CoreGraphics.h>

@interface XSOverlayView : NSView
@property (nonatomic, strong) NSImage *screenImage;
@property (nonatomic, assign) NSRect selection;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, assign) BOOL windowMode;
@property (nonatomic, assign) NSRect highlightedWindow;
@property (nonatomic, weak) NSScreen *hostScreen;
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

@implementation XSOverlayView {
    NSPoint _start;
    NSTrackingArea *_track;
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

- (void)mouseDown:(NSEvent *)event {
    if (self.windowMode) {
        [self confirmWindow];
        return;
    }
    self.dragging = YES;
    _start = [self convertPoint:event.locationInWindow fromView:nil];
    self.selection = NSMakeRect(_start.x, _start.y, 0, 0);
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.dragging) return;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    self.selection = NSIntegralRect(NSMakeRect(MIN(_start.x, p.x), MIN(_start.y, p.y),
                                               fabs(p.x - _start.x), fabs(p.y - _start.y)));
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    if (!self.dragging) return;
    self.dragging = NO;
    if (self.selection.size.width < 4 || self.selection.size.height < 4) {
        self.selection = NSZeroRect;
        [self setNeedsDisplay:YES];
        return;
    }
    [self confirmSelection];
}

- (void)mouseMoved:(NSEvent *)event {
    if (self.windowMode) {
        NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
        [self highlightWindowAtPoint:p];
    }
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 53) {
        if (self.onCancel) self.onCancel();
        return;
    }
    if (event.keyCode == 49) {
        self.windowMode = !self.windowMode;
        self.selection = NSZeroRect;
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

@implementation XSCaptureController {
    NSMutableArray<XSOverlayWindow *> *_windows;
    BOOL _plainMode;
}

+ (instancetype)shared {
    static XSCaptureController *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [XSCaptureController new]; });
    return c;
}

- (void)beginCapture {
    _plainMode = NO;
    [self start];
}

- (void)beginPlainCapture {
    _plainMode = YES;
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
    BOOL plain = _plainMode;
    _plainMode = NO;
    [self dismiss];
    [NSApp unhide:nil];
    if (!image || image.size.width < 2) return;
    if (plain) {
        NSPasteboard *pb = NSPasteboard.generalPasteboard;
        [pb clearContents];
        [pb writeObjects:@[image]];
        [[XSPinController shared] rememberPlainCaptureAtScreenRect:screenRect pasteboardChangeCount:pb.changeCount];
        [self showCopiedHUD];
        return;
    }
    [NSApp activateIgnoringOtherApps:YES];
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
