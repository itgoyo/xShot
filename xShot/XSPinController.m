#import "XSPinController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface XSPinContentView : NSView
@property (nonatomic, strong) NSImage *image;
@property (nonatomic, weak) NSWindow *hostWindow;
@property (nonatomic, copy) void (^onClose)(void);
@end

@implementation XSPinContentView {
    NSPoint _dragStart;
    NSPoint _winOrigin;
    BOOL _dragging;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isOpaque { return NO; }
- (void)drawRect:(NSRect)dirty {
    NSRect r = NSInsetRect(self.bounds, 10, 10);
    [self.image drawInRect:r fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
    NSRect close = NSMakeRect(NSMaxX(r) - 22, NSMaxY(r) - 22, 18, 18);
    [[[NSColor blackColor] colorWithAlphaComponent:0.45] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:close] fill];
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: NSColor.whiteColor
    };
    [@"✕" drawAtPoint:NSMakePoint(close.origin.x + 3.5, close.origin.y + 1.5) withAttributes:attrs];
}
- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect r = NSInsetRect(self.bounds, 10, 10);
    NSRect close = NSMakeRect(NSMaxX(r) - 22, NSMaxY(r) - 22, 18, 18);
    if (NSPointInRect(p, close)) {
        if (self.onClose) self.onClose();
        return;
    }
    _dragging = YES;
    _dragStart = event.locationInWindow;
    _winOrigin = self.hostWindow.frame.origin;
}
- (void)mouseDragged:(NSEvent *)event {
    if (!_dragging) return;
    NSPoint cur = event.locationInWindow;
    // convert delta to screen
    NSPoint screenStart = [self.hostWindow convertPointToScreen:_dragStart];
    NSPoint screenCur = [self.hostWindow convertPointToScreen:cur];
    CGFloat dx = screenCur.x - screenStart.x;
    CGFloat dy = screenCur.y - screenStart.y;
    NSRect f = self.hostWindow.frame;
    f.origin = NSMakePoint(_winOrigin.x + dx, _winOrigin.y + dy);
    [self.hostWindow setFrame:f display:YES];
}
- (void)mouseUp:(NSEvent *)event { _dragging = NO; }
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

- (void)pinClipboardIfImage {
    NSImage *img = [self clipboardImage];
    if (!img || img.size.width < 2 || img.size.height < 2) return;
    NSScreen *s = NSScreen.mainScreen;
    NSRect sf = s.visibleFrame;
    NSRect dest = NSMakeRect(sf.origin.x + 40,
                             sf.origin.y + sf.size.height - img.size.height - 80,
                             img.size.width, img.size.height);
    [self pinImage:img atScreenRect:dest];
}

- (void)pinImage:(NSImage *)image atScreenRect:(NSRect)screenRect {
    if (!image || image.size.width < 2) return;
    CGFloat pad = 10;
    NSSize img = image.size;
    NSRect frame = screenRect;
    if (frame.size.width < 4 || frame.size.height < 4) {
        NSScreen *s = NSScreen.mainScreen;
        NSRect sf = s.frame;
        frame = NSMakeRect(sf.origin.x + (sf.size.width - img.width) / 2.0,
                           sf.origin.y + (sf.size.height - img.height) / 2.0,
                           img.width, img.height);
    }
    // keep image aspect, use capture rect size if possible
    frame.size = NSMakeSize(img.width + pad * 2, img.height + pad * 2);
    // if original rect had position, use its origin
    if (screenRect.size.width > 4) {
        frame.origin = screenRect.origin;
        // adjust if image smaller/larger than selection — keep top-left of selection
        frame.origin.y = screenRect.origin.y + screenRect.size.height - frame.size.height;
        if (frame.size.height > screenRect.size.height) {
            frame.origin.y = screenRect.origin.y;
        }
    }

    XSPinWindow *win = [[XSPinWindow alloc] initWithContentRect:frame
                                                      styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
    win.level = NSFloatingWindowLevel + 2;
    win.opaque = NO;
    win.backgroundColor = NSColor.clearColor;
    win.hasShadow = YES;
    win.movableByWindowBackground = NO;
    win.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorStationary;
    win.releasedWhenClosed = NO;

    XSPinContentView *view = [[XSPinContentView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
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
    [_pins addObject:win];
    NSApp.activationPolicy = NSApplicationActivationPolicyAccessory;
}

- (void)closeAll {
    for (NSWindow *w in _pins) [w close];
    [_pins removeAllObjects];
}

@end
