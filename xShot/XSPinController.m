#import "XSPinController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface XSPinContentView : NSView
@property (nonatomic, strong) NSImage *image;
@property (nonatomic, weak) NSWindow *hostWindow;
@property (nonatomic, copy) void (^onClose)(void);
@end

@implementation XSPinContentView {
    NSPoint _grabOffset;
    BOOL _dragging;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)dirty {
    [self.image drawInRect:self.bounds fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1];
}
- (void)mouseDown:(NSEvent *)event {
    NSPoint screen = [NSEvent mouseLocation];
    NSRect f = self.hostWindow.frame;
    _grabOffset = NSMakePoint(screen.x - f.origin.x, screen.y - f.origin.y);
    _dragging = YES;
}
- (void)mouseDragged:(NSEvent *)event {
    if (!_dragging) return;
    NSPoint screen = [NSEvent mouseLocation];
    [self.hostWindow setFrameOrigin:NSMakePoint(screen.x - _grabOffset.x, screen.y - _grabOffset.y)];
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
