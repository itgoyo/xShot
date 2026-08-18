#import "XSColorPickerController.h"
#import <CoreGraphics/CoreGraphics.h>

@interface XSColorOverlayView : NSView
@property (nonatomic, strong) NSImage *screenImage;
@property (nonatomic, assign) NSPoint cursor;
@property (nonatomic, strong) NSColor *currentColor;
@property (nonatomic, copy) void (^onPick)(NSColor *color);
@property (nonatomic, copy) void (^onCancel)(void);
@end

@implementation XSColorOverlayView {
    NSTrackingArea *_track;
    CGImageRef _cgImage;
}

- (void)dealloc {
    if (_cgImage) {
        CGImageRelease(_cgImage);
        _cgImage = NULL;
    }
}

- (void)setScreenImage:(NSImage *)screenImage {
    _screenImage = screenImage;
    if (_cgImage) {
        CGImageRelease(_cgImage);
        _cgImage = NULL;
    }
    if (!screenImage) return;
    NSRect proposed = NSMakeRect(0, 0, screenImage.size.width, screenImage.size.height);
    CGImageRef cg = [screenImage CGImageForProposedRect:&proposed context:nil hints:nil];
    if (cg) _cgImage = CGImageRetain(cg);
}

- (BOOL)acceptsFirstResponder { return YES; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_track) [self removeTrackingArea:_track];
    _track = [[NSTrackingArea alloc] initWithRect:self.bounds
                                          options:NSTrackingMouseMoved | NSTrackingActiveAlways | NSTrackingInVisibleRect | NSTrackingMouseEnteredAndExited
                                            owner:self userInfo:nil];
    [self addTrackingArea:_track];
}

- (NSColor *)sampleAtViewPoint:(NSPoint)p {
    if (!_cgImage) return NSColor.blackColor;
    CGFloat vw = MAX(1.0, self.bounds.size.width);
    CGFloat vh = MAX(1.0, self.bounds.size.height);
    size_t pw = CGImageGetWidth(_cgImage);
    size_t ph = CGImageGetHeight(_cgImage);
    if (pw == 0 || ph == 0) return NSColor.blackColor;

    CGFloat px = MIN(MAX(p.x, 0), vw - 0.0001);
    CGFloat py = MIN(MAX(p.y, 0), vh - 0.0001);
    NSInteger ix = (NSInteger)floor(px * (CGFloat)pw / vw);
    // 视图原点在左下，CGImage 原点在左上
    NSInteger iy = (NSInteger)floor((vh - py) * (CGFloat)ph / vh);
    if (iy >= (NSInteger)ph) iy = (NSInteger)ph - 1;
    ix = MIN(MAX(ix, 0), (NSInteger)pw - 1);
    iy = MIN(MAX(iy, 0), (NSInteger)ph - 1);

    CGImageRef pixel = CGImageCreateWithImageInRect(_cgImage, CGRectMake(ix, iy, 1, 1));
    if (!pixel) return NSColor.blackColor;
    unsigned char rgba[4] = {0, 0, 0, 255};
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(rgba, 1, 1, 8, 4, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    if (ctx) {
        CGContextSetBlendMode(ctx, kCGBlendModeCopy);
        CGContextDrawImage(ctx, CGRectMake(0, 0, 1, 1), pixel);
        CGContextRelease(ctx);
    }
    CGColorSpaceRelease(cs);
    CGImageRelease(pixel);

    CGFloat a = rgba[3] / 255.0;
    if (a <= 0.001) return NSColor.blackColor;
    return [NSColor colorWithSRGBRed:(rgba[0] / 255.0) / a
                               green:(rgba[1] / 255.0) / a
                                blue:(rgba[2] / 255.0) / a
                               alpha:1];
}
- (void)drawRect:(NSRect)dirty {
    [self.screenImage drawInRect:self.bounds fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1];
    if (!self.currentColor) return;
    NSPoint p = self.cursor;
    CGFloat loupe = 88;
    NSRect loupeRect = NSMakeRect(p.x + 18, p.y - loupe - 18, loupe, loupe);
    if (NSMaxX(loupeRect) > self.bounds.size.width) loupeRect.origin.x = p.x - loupe - 18;
    if (loupeRect.origin.y < 8) loupeRect.origin.y = p.y + 18;

    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:loupeRect];
    // magnify region
    CGFloat sx = self.screenImage.size.width / self.bounds.size.width;
    CGFloat sy = self.screenImage.size.height / self.bounds.size.height;
    CGFloat sample = 9;
    NSRect src = NSMakeRect((p.x - sample / 2) * sx, (p.y - sample / 2) * sy, sample * sx, sample * sy);
    [circle setClip];
    [self.screenImage drawInRect:loupeRect fromRect:src operation:NSCompositingOperationCopy fraction:1];

    [[NSColor whiteColor] setStroke];
    circle = [NSBezierPath bezierPathWithOvalInRect:loupeRect];
    circle.lineWidth = 3;
    [circle stroke];
    [self.currentColor setFill];
    NSRect swatch = NSInsetRect(loupeRect, loupe * 0.28, loupe * 0.28);
    [[NSBezierPath bezierPathWithOvalInRect:swatch] fill];
    [[NSColor whiteColor] setStroke];
    NSBezierPath *sw = [NSBezierPath bezierPathWithOvalInRect:swatch];
    sw.lineWidth = 2;
    [sw stroke];

    NSString *hex = [self hexFromColor:self.currentColor];
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: NSColor.whiteColor
    };
    NSSize ts = [hex sizeWithAttributes:attrs];
    NSRect badge = NSMakeRect(NSMidX(loupeRect) - ts.width / 2 - 8, NSMinY(loupeRect) - 28, ts.width + 16, 22);
    [[[NSColor blackColor] colorWithAlphaComponent:0.72] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:badge xRadius:6 yRadius:6] fill];
    [hex drawAtPoint:NSMakePoint(badge.origin.x + 8, badge.origin.y + 4) withAttributes:attrs];
}
- (NSString *)hexFromColor:(NSColor *)c {
    c = [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (int)llround(c.redComponent * 255),
            (int)llround(c.greenComponent * 255),
            (int)llround(c.blueComponent * 255)];
}
- (void)mouseEntered:(NSEvent *)event { [self mouseMoved:event]; }
- (void)mouseMoved:(NSEvent *)event {
    self.cursor = [self convertPoint:event.locationInWindow fromView:nil];
    self.currentColor = [self sampleAtViewPoint:self.cursor];
    [self setNeedsDisplay:YES];
}
- (void)mouseDown:(NSEvent *)event {
    self.cursor = [self convertPoint:event.locationInWindow fromView:nil];
    self.currentColor = [self sampleAtViewPoint:self.cursor];
    if (self.onPick && self.currentColor) self.onPick(self.currentColor);
}
- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 53 && self.onCancel) self.onCancel();
}
@end

@interface XSColorOverlayWindow : NSPanel
@end
@implementation XSColorOverlayWindow
- (BOOL)canBecomeKeyWindow { return YES; }
@end

@implementation XSColorPickerController {
    NSMutableArray<NSWindow *> *_windows;
}

+ (instancetype)shared {
    static XSColorPickerController *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [XSColorPickerController new]; });
    return c;
}

- (void)beginPick {
    if (_windows.count) [self dismiss];
    if (!CGPreflightScreenCaptureAccess()) {
        CGRequestScreenCaptureAccess();
        NSAlert *a = [NSAlert new];
        a.messageText = @"需要屏幕录制权限";
        a.informativeText = @"系统设置 → 隐私与安全性 → 屏幕录制，勾选 xShot。";
        [a runModal];
        return;
    }
    [NSApp hide:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self showOverlays];
    });
}

- (NSImage *)imageForScreen:(NSScreen *)screen {
    CGDirectDisplayID did = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
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
        XSColorOverlayWindow *win = [[XSColorOverlayWindow alloc] initWithContentRect:screen.frame
                                                                            styleMask:NSWindowStyleMaskBorderless
                                                                              backing:NSBackingStoreBuffered
                                                                                defer:NO];
        win.level = NSScreenSaverWindowLevel;
        win.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
        win.releasedWhenClosed = NO;
        XSColorOverlayView *view = [[XSColorOverlayView alloc] initWithFrame:win.contentView.bounds];
        view.screenImage = shot;
        __weak typeof(self) weakSelf = self;
        view.onPick = ^(NSColor *color) {
            [weakSelf finishWithColor:color];
        };
        view.onCancel = ^{
            [weakSelf dismiss];
            [NSApp unhide:nil];
        };
        win.contentView = view;
        [win setFrame:screen.frame display:YES];
        [win makeKeyAndOrderFront:nil];
        [_windows addObject:win];
    }
    [NSApp unhide:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [_windows.firstObject makeKeyWindow];
    [_windows.firstObject makeFirstResponder:_windows.firstObject.contentView];
    [[NSCursor crosshairCursor] set];
}

- (void)finishWithColor:(NSColor *)color {
    color = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    NSString *hex = [NSString stringWithFormat:@"#%02X%02X%02X",
                     (int)llround(color.redComponent * 255),
                     (int)llround(color.greenComponent * 255),
                     (int)llround(color.blueComponent * 255)];
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb clearContents];
    [pb setString:hex forType:NSPasteboardTypeString];
    [self dismiss];
    [NSApp unhide:nil];

    // brief HUD
    NSPanel *hud = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 160, 56)
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
    NSTextField *label = [NSTextField labelWithString:[NSString stringWithFormat:@"已复制 %@", hex]];
    label.textColor = NSColor.whiteColor;
    label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    label.alignment = NSTextAlignmentCenter;
    label.frame = NSMakeRect(0, 18, 160, 20);
    [v addSubview:label];
    hud.contentView = v;
    NSScreen *s = NSScreen.mainScreen;
    NSRect sf = s.visibleFrame;
    [hud setFrameOrigin:NSMakePoint(sf.origin.x + (sf.size.width - 160) / 2, sf.origin.y + 80)];
    [hud orderFront:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [hud close];
    });
}

- (void)dismiss {
    for (NSWindow *w in _windows) {
        if ([w.contentView isKindOfClass:XSColorOverlayView.class]) {
            ((XSColorOverlayView *)w.contentView).screenImage = nil;
        }
        [w close];
    }
    [_windows removeAllObjects];
    [[NSCursor arrowCursor] set];
}

@end
