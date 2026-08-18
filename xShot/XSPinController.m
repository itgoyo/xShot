#import "XSPinController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

typedef NS_ENUM(NSInteger, XSPinHandle) {
    XSPinHandleNone = 0,
    XSPinHandleBL,
    XSPinHandleBR,
    XSPinHandleTL,
    XSPinHandleTR,
};

@interface XSPinContentView : NSView
@property (nonatomic, strong) NSImage *image;
@property (nonatomic, weak) NSWindow *hostWindow;
@property (nonatomic, copy) void (^onClose)(void);
@end

@implementation XSPinContentView {
    NSPoint _grabOffset;
    NSPoint _anchor;
    BOOL _dragging;
    BOOL _resizing;
    BOOL _hovering;
    XSPinHandle _handle;
    NSTrackingArea *_track;
}

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isOpaque { return YES; }

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_track) [self removeTrackingArea:_track];
    _track = [[NSTrackingArea alloc] initWithRect:self.bounds
                                          options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                            owner:self userInfo:nil];
    [self addTrackingArea:_track];
}

- (CGFloat)handleHit {
    return MAX(16.0, MIN(28.0, MIN(self.bounds.size.width, self.bounds.size.height) * 0.18));
}

- (XSPinHandle)handleAtPoint:(NSPoint)p {
    CGFloat z = [self handleHit];
    NSSize s = self.bounds.size;
    if (NSPointInRect(p, NSMakeRect(0, 0, z, z))) return XSPinHandleBL;
    if (NSPointInRect(p, NSMakeRect(s.width - z, 0, z, z))) return XSPinHandleBR;
    if (NSPointInRect(p, NSMakeRect(0, s.height - z, z, z))) return XSPinHandleTL;
    if (NSPointInRect(p, NSMakeRect(s.width - z, s.height - z, z, z))) return XSPinHandleTR;
    return XSPinHandleNone;
}

- (void)applyCursorAtPoint:(NSPoint)p {
    if (_resizing || [self handleAtPoint:p] != XSPinHandleNone) {
        [[NSCursor crosshairCursor] set];
    } else if (_dragging) {
        [[NSCursor closedHandCursor] set];
    } else {
        [[NSCursor openHandCursor] set];
    }
}

- (void)drawRect:(NSRect)dirty {
    [self.image drawInRect:self.bounds
                  fromRect:NSZeroRect
                 operation:NSCompositingOperationCopy
                  fraction:1
            respectFlipped:YES
                     hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
    if (!_hovering && !_resizing) return;
    CGFloat z = 7;
    NSSize s = self.bounds.size;
    NSRect handles[] = {
        NSMakeRect(1, 1, z, z),
        NSMakeRect(s.width - z - 1, 1, z, z),
        NSMakeRect(1, s.height - z - 1, z, z),
        NSMakeRect(s.width - z - 1, s.height - z - 1, z, z),
    };
    for (int i = 0; i < 4; i++) {
        [[NSColor colorWithWhite:1 alpha:0.95] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:handles[i] xRadius:1 yRadius:1] fill];
        [[NSColor colorWithWhite:0.15 alpha:0.85] setStroke];
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(handles[i], 0.5, 0.5) xRadius:1 yRadius:1];
        path.lineWidth = 1;
        [path stroke];
    }
}

- (void)mouseEntered:(NSEvent *)event {
    _hovering = YES;
    [self applyCursorAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event {
    _hovering = NO;
    if (!_dragging && !_resizing) [[NSCursor arrowCursor] set];
    [self setNeedsDisplay:YES];
}

- (void)mouseMoved:(NSEvent *)event {
    [self applyCursorAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint local = [self convertPoint:event.locationInWindow fromView:nil];
    NSPoint screen = [NSEvent mouseLocation];
    NSRect f = self.hostWindow.frame;
    _handle = [self handleAtPoint:local];
    if (_handle != XSPinHandleNone) {
        _resizing = YES;
        _dragging = NO;
        switch (_handle) {
            case XSPinHandleTR: _anchor = f.origin; break;
            case XSPinHandleTL: _anchor = NSMakePoint(NSMaxX(f), f.origin.y); break;
            case XSPinHandleBR: _anchor = NSMakePoint(f.origin.x, NSMaxY(f)); break;
            case XSPinHandleBL: _anchor = NSMakePoint(NSMaxX(f), NSMaxY(f)); break;
            default: break;
        }
        [[NSCursor crosshairCursor] set];
        return;
    }
    _resizing = NO;
    _dragging = YES;
    _grabOffset = NSMakePoint(screen.x - f.origin.x, screen.y - f.origin.y);
    [[NSCursor closedHandCursor] set];
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint screen = [NSEvent mouseLocation];
    if (_resizing) {
        NSSize img = self.image.size;
        if (img.width < 1 || img.height < 1) return;
        CGFloat aw = fabs(screen.x - _anchor.x);
        CGFloat ah = fabs(screen.y - _anchor.y);
        CGFloat s = MAX(aw / img.width, ah / img.height);
        s = MAX(s, 48.0 / MIN(img.width, img.height));
        CGFloat w = img.width * s;
        CGFloat h = img.height * s;
        NSRect frame = NSZeroRect;
        frame.size = NSMakeSize(w, h);
        switch (_handle) {
            case XSPinHandleTR: frame.origin = _anchor; break;
            case XSPinHandleTL: frame.origin = NSMakePoint(_anchor.x - w, _anchor.y); break;
            case XSPinHandleBR: frame.origin = NSMakePoint(_anchor.x, _anchor.y - h); break;
            case XSPinHandleBL: frame.origin = NSMakePoint(_anchor.x - w, _anchor.y - h); break;
            default: return;
        }
        [self.hostWindow setFrame:frame display:YES];
        return;
    }
    if (!_dragging) return;
    [self.hostWindow setFrameOrigin:NSMakePoint(screen.x - _grabOffset.x, screen.y - _grabOffset.y)];
}

- (void)mouseUp:(NSEvent *)event {
    _dragging = NO;
    _resizing = NO;
    _handle = XSPinHandleNone;
    [self applyCursorAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 53 && self.onClose) self.onClose();
}
@end

@interface XSPinWindow : NSPanel
@end
@implementation XSPinWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@implementation XSPinController {
    NSMutableArray<NSWindow *> *_pins;
    NSRect _lastPlainScreenRect;
    NSInteger _lastPlainPasteboardChangeCount;
    BOOL _hasLastPlainCapture;
}

+ (instancetype)shared {
    static XSPinController *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [XSPinController new]; });
    return c;
}

- (instancetype)init {
    self = [super init];
    if (self) _pins = [NSMutableArray array];
    return self;
}

- (NSImage *)clipboardImage {
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    NSArray<NSPasteboardType> *types = pb.types ?: @[];
    NSArray<NSString *> *imageTypes = @[
        NSPasteboardTypePNG,
        NSPasteboardTypeTIFF,
        @"public.jpeg",
        @"public.jpeg-2000",
        @"public.heic",
        @"public.heif",
        @"public.webp",
        @"com.compuserve.gif",
        @"com.microsoft.bmp",
        @"org.webmproject.webp",
    ];
    BOOL hasImageType = NO;
    for (NSPasteboardType t in types) {
        if ([imageTypes containsObject:t]) { hasImageType = YES; break; }
        if ([t hasPrefix:@"public.image"]) { hasImageType = YES; break; }
    }
    if (!hasImageType) {
        NSURL *url = [NSURL URLFromPasteboard:pb];
        if (url.isFileURL) {
            UTType *ut = [UTType typeWithFilenameExtension:url.pathExtension.lowercaseString];
            if (ut && [ut conformsToType:UTTypeImage] && ![ut conformsToType:UTTypePDF]) {
                return [[NSImage alloc] initWithContentsOfURL:url];
            }
        }
        return nil;
    }
    return [[NSImage alloc] initWithPasteboard:pb];
}

- (void)rememberPlainCaptureAtScreenRect:(NSRect)screenRect pasteboardChangeCount:(NSInteger)changeCount {
    _lastPlainScreenRect = screenRect;
    _lastPlainPasteboardChangeCount = changeCount;
    _hasLastPlainCapture = screenRect.size.width >= 4 && screenRect.size.height >= 4;
}

- (void)pinClipboardIfImage {
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    NSImage *img = [self clipboardImage];
    if (!img || img.size.width < 2 || img.size.height < 2) return;
    NSRect dest = NSZeroRect;
    if (_hasLastPlainCapture && pb.changeCount == _lastPlainPasteboardChangeCount) {
        dest = _lastPlainScreenRect;
    } else {
        NSScreen *s = NSScreen.mainScreen;
        NSRect sf = s.visibleFrame;
        dest = NSMakeRect(sf.origin.x + 40,
                          sf.origin.y + sf.size.height - img.size.height - 80,
                          img.size.width, img.size.height);
    }
    [self pinImage:img atScreenRect:dest];
}

- (void)pinImage:(NSImage *)image atScreenRect:(NSRect)screenRect {
    if (!image || image.size.width < 2) return;
    NSRect frame;
    if (screenRect.size.width >= 4 && screenRect.size.height >= 4) {
        frame = screenRect;
    } else {
        NSSize img = image.size;
        NSScreen *s = NSScreen.mainScreen;
        NSRect sf = s.frame;
        frame = NSMakeRect(sf.origin.x + (sf.size.width - img.width) / 2.0,
                           sf.origin.y + (sf.size.height - img.height) / 2.0,
                           img.width, img.height);
    }

    XSPinWindow *win = [[XSPinWindow alloc] initWithContentRect:frame
                                                      styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
    win.level = NSFloatingWindowLevel + 2;
    win.opaque = YES;
    win.backgroundColor = NSColor.blackColor;
    win.hasShadow = YES;
    win.movableByWindowBackground = NO;
    win.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    win.releasedWhenClosed = NO;
    win.animationBehavior = NSWindowAnimationBehaviorNone;

    XSPinContentView *view = [[XSPinContentView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    view.image = image;
    view.hostWindow = win;
    __weak typeof(self) weakSelf = self;
    __weak NSWindow *weakWin = win;
    view.onClose = ^{
        NSWindow *w = weakWin;
        XSPinController *strong = weakSelf;
        [w close];
        if (strong) [strong->_pins removeObject:w];
    };
    win.contentView = view;
    [win setFrame:frame display:YES];
    [win orderFront:nil];
    [win makeKeyAndOrderFront:nil];
    [win makeFirstResponder:view];
    [_pins addObject:win];
    NSApp.activationPolicy = NSApplicationActivationPolicyAccessory;
}

- (void)closeAll {
    for (NSWindow *w in _pins) [w close];
    [_pins removeAllObjects];
}

@end
