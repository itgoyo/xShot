#import "XSEditorWindowController.h"
#import "XSPreset.h"
#import "XSPresetStore.h"
#import "XSImageRenderer.h"
#import "XSBackgroundCatalog.h"
#import "XSRedactor.h"
#import "XSSettingsWindowController.h"
#import "XSHotKeyManager.h"
#import "XSPinController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSColor *XSCream(void) {
    return [NSColor colorWithCalibratedRed:0.965 green:0.957 blue:0.941 alpha:1];
}
static NSColor *XSSidebar(void) {
    return [NSColor colorWithCalibratedRed:0.925 green:0.918 blue:0.902 alpha:1];
}

@interface XSCanvasView : NSView <NSDraggingSource>
@property (nonatomic, strong) NSImage *rendered;
@property (nonatomic, assign) CGFloat zoom;
@property (nonatomic, copy) void (^onDoubleClick)(void);
@end

@implementation XSCanvasView
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _zoom = 1;
        self.wantsLayer = YES;
    }
    return self;
}
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)dirty {
    [XSCream() setFill];
    NSRectFill(self.bounds);
    if (!self.rendered) return;
    NSSize sz = self.rendered.size;
    CGFloat z = self.zoom;
    NSSize draw = NSMakeSize(sz.width * z, sz.height * z);
    NSRect r = NSMakeRect((self.bounds.size.width - draw.width) / 2.0,
                          (self.bounds.size.height - draw.height) / 2.0,
                          draw.width, draw.height);
    BOOL none = [XSPresetStore.shared.current.backgroundId isEqualToString:@"none"];
    if (none) {
        [[NSColor colorWithWhite:0.92 alpha:1] setFill];
        NSRectFill(r);
        [[NSColor colorWithWhite:0.8 alpha:1] setFill];
        CGFloat cell = 10;
        for (int y = 0; y < draw.height / cell + 1; y++)
            for (int x = 0; x < draw.width / cell + 1; x++)
                if ((x + y) % 2 == 0)
                    NSRectFill(NSMakeRect(r.origin.x + x * cell, r.origin.y + y * cell, cell, cell));
    }
    [self.rendered drawInRect:r fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
}
- (NSRect)imageRect {
    NSSize sz = self.rendered.size;
    CGFloat z = self.zoom;
    NSSize draw = NSMakeSize(sz.width * z, sz.height * z);
    return NSMakeRect((self.bounds.size.width - draw.width) / 2.0,
                      (self.bounds.size.height - draw.height) / 2.0,
                      draw.width, draw.height);
}
- (void)mouseDown:(NSEvent *)event {
    if (event.clickCount == 2) {
        if (self.onDoubleClick) self.onDoubleClick();
        return;
    }
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(p, [self imageRect]) || !self.rendered) return;
    NSDraggingItem *item = [[NSDraggingItem alloc] initWithPasteboardWriter:self.rendered];
    [item setDraggingFrame:[self imageRect] contents:self.rendered];
    [self beginDraggingSessionWithItems:@[item] event:event source:self];
}
- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)ctx {
    return NSDragOperationCopy;
}
@end

@interface XSFlippedView : NSView
@end
@implementation XSFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface XSEditorWindowController () <NSWindowDelegate>
@end

@implementation XSEditorWindowController {
    NSImage *_source;
    NSImage *_processed;
    NSImage *_rendered;
    XSCanvasView *_canvas;
    NSScrollView *_sidebarScroll;
    NSView *_sidebar;
    NSView *_bottomBar;
    NSPopUpButton *_presetPopup;
    NSSlider *_padSlider;
    NSSlider *_insetSlider;
    NSSlider *_radiusSlider;
    NSSlider *_shadowSlider;
    NSSlider *_blurSlider;
    NSButton *_balanceCheck;
    NSMutableArray<NSButton *> *_bgButtons;
    NSMutableArray<NSButton *> *_ratioButtons;
    NSButton *_redactCheck;
    NSButton *_wmCheck;
    NSTextField *_wmField;
    NSTextField *_hint;
    NSPopUpButton *_zoomPopup;
    NSInteger _emailCount;
    BOOL _updating;
    NSUInteger _renderToken;
    BOOL _copyWhenRendered;
}

+ (void)prewarm {
    [XSImageRenderer warmup];
}

+ (instancetype)shared {
    static XSEditorWindowController *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [[XSEditorWindowController alloc] init]; });
    return c;
}

- (instancetype)init {
    NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1120, 740)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                  backing:NSBackingStoreBuffered defer:NO];
    win.title = @"";
    win.minSize = NSMakeSize(860, 560);
    win.releasedWhenClosed = NO;
    win.backgroundColor = XSCream();
    win.titlebarAppearsTransparent = YES;
    self = [super initWithWindow:win];
    if (self) {
        win.delegate = self;
        [self buildChrome];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onResize) name:NSWindowDidResizeNotification object:win];
    }
    return self;
}

- (NSSlider *)sliderMin:(CGFloat)min max:(CGFloat)max action:(SEL)sel {
    NSSlider *s = [NSSlider sliderWithValue:0 minValue:min maxValue:max target:self action:sel];
    s.controlSize = NSControlSizeSmall;
    return s;
}

- (NSTextField *)label:(NSString *)t {
    NSTextField *f = [NSTextField labelWithString:t];
    f.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    f.textColor = NSColor.labelColor;
    return f;
}

- (void)buildChrome {
    NSView *root = self.window.contentView;
    _canvas = [[XSCanvasView alloc] initWithFrame:NSZeroRect];
    __weak typeof(self) weakSelf = self;
    _canvas.onDoubleClick = ^{ [weakSelf copyAndClose]; };
    [root addSubview:_canvas];

    _sidebarScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _sidebarScroll.drawsBackground = YES;
    _sidebarScroll.backgroundColor = XSSidebar();
    _sidebarScroll.hasVerticalScroller = YES;
    _sidebarScroll.borderType = NSNoBorder;
    _sidebarScroll.autohidesScrollers = YES;
    _sidebar = [[XSFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 300, 820)];
    _sidebar.wantsLayer = YES;
    _sidebar.layer.backgroundColor = XSSidebar().CGColor;
    _sidebarScroll.documentView = _sidebar;
    [root addSubview:_sidebarScroll];

    _bottomBar = [[NSView alloc] initWithFrame:NSZeroRect];
    [root addSubview:_bottomBar];

    NSButton *share = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"square.and.arrow.up" accessibilityDescription:@"Share"] target:self action:@selector(share:)];
    share.bordered = NO;
    share.frame = NSMakeRect(0, 0, 24, 24);
    NSTitlebarAccessoryViewController *acc = [NSTitlebarAccessoryViewController new];
    NSView *accView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 36, 24)];
    share.frame = NSMakeRect(4, 0, 24, 24);
    [accView addSubview:share];
    acc.view = accView;
    acc.layoutAttribute = NSLayoutAttributeRight;
    [self.window addTitlebarAccessoryViewController:acc];

    [self buildSidebar];
    [self buildBottom];
}

- (void)buildSidebar {
    CGFloat x = 16, w = 268, y = 0;
    // laid out in layoutSidebar
    _presetPopup = [NSPopUpButton new];
    _presetPopup.target = self;
    _presetPopup.action = @selector(presetChanged:);
    [_sidebar addSubview:_presetPopup];

    NSButton *trash = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"trash" accessibilityDescription:@"Delete preset"] target:self action:@selector(deletePreset:)];
    trash.bordered = NO;
    trash.tag = 9001;
    [_sidebar addSubview:trash];

    [_sidebar addSubview:[self namedLabel:@"Padding" tag:100]];
    _padSlider = [self sliderMin:0 max:160 action:@selector(styleChanged:)];
    [_sidebar addSubview:_padSlider];

    [_sidebar addSubview:[self namedLabel:@"Inset" tag:101]];
    _insetSlider = [self sliderMin:0 max:80 action:@selector(styleChanged:)];
    [_sidebar addSubview:_insetSlider];
    _balanceCheck = [NSButton checkboxWithTitle:@"Balance" target:self action:@selector(styleChanged:)];
    _balanceCheck.font = [NSFont systemFontOfSize:11];
    [_sidebar addSubview:_balanceCheck];

    [_sidebar addSubview:[self namedLabel:@"Border Radius" tag:102]];
    _radiusSlider = [self sliderMin:0 max:80 action:@selector(styleChanged:)];
    [_sidebar addSubview:_radiusSlider];

    [_sidebar addSubview:[self namedLabel:@"Shadow" tag:103]];
    _shadowSlider = [self sliderMin:0 max:80 action:@selector(styleChanged:)];
    [_sidebar addSubview:_shadowSlider];

    [_sidebar addSubview:[self namedLabel:@"Blur" tag:106]];
    _blurSlider = [self sliderMin:0 max:50 action:@selector(styleChanged:)];
    [_sidebar addSubview:_blurSlider];

    [_sidebar addSubview:[self namedLabel:@"Background" tag:104]];
    _bgButtons = [NSMutableArray array];
    for (XSBackgroundItem *item in XSBackgroundCatalog.items) {
        NSButton *b = [NSButton new];
        b.imagePosition = NSImageOnly;
        b.bordered = YES;
        b.bezelStyle = NSBezelStyleRegularSquare;
        b.toolTip = item.title;
        b.identifier = item.identifier;
        b.target = self;
        b.action = @selector(bgClicked:);
        [_sidebar addSubview:b];
        [_bgButtons addObject:b];
        NSString *bgId = item.identifier;
        b.image = [XSBackgroundCatalog thumbnailForId:bgId size:NSMakeSize(72, 44)];
        NSTextField *cap = [NSTextField labelWithString:item.title];
        cap.font = [NSFont systemFontOfSize:9];
        cap.alignment = NSTextAlignmentCenter;
        cap.textColor = NSColor.secondaryLabelColor;
        cap.identifier = [NSString stringWithFormat:@"cap-%@", item.identifier];
        [_sidebar addSubview:cap];
    }

    [_sidebar addSubview:[self namedLabel:@"Ratio / Size" tag:105]];
    _ratioButtons = [NSMutableArray array];
    NSArray *ratios = @[
        @"auto", @"4:3", @"3:2", @"16:9", @"1:1",
        @"twitter", @"facebook", @"instagram", @"linkedin",
        @"youtube", @"pinterest", @"reddit", @"snapchat"
    ];
    NSArray *titles = @[
        @"Auto", @"4:3", @"3:2", @"16:9", @"1:1",
        @"Twitter", @"Facebook", @"Instagram", @"LinkedIn",
        @"YouTube", @"Pinterest", @"Reddit", @"Snapchat"
    ];
    for (NSUInteger i = 0; i < ratios.count; i++) {
        NSButton *b = [NSButton buttonWithTitle:titles[i] target:self action:@selector(ratioClicked:)];
        b.bezelStyle = NSBezelStyleRounded;
        b.identifier = ratios[i];
        b.font = [NSFont systemFontOfSize:11];
        b.toolTip = titles[i];
        if (@available(macOS 11.0, *)) {
            b.controlSize = NSControlSizeSmall;
        }
        [_sidebar addSubview:b];
        [_ratioButtons addObject:b];
    }

    _redactCheck = [NSButton checkboxWithTitle:@"Redact email addresses" target:self action:@selector(styleChanged:)];
    _redactCheck.font = [NSFont systemFontOfSize:12];
    [_sidebar addSubview:_redactCheck];
    _wmCheck = [NSButton checkboxWithTitle:@"Show watermark" target:self action:@selector(styleChanged:)];
    _wmCheck.font = [NSFont systemFontOfSize:12];
    [_sidebar addSubview:_wmCheck];
    _wmField = [NSTextField new];
    _wmField.font = [NSFont systemFontOfSize:12];
    _wmField.target = self;
    _wmField.action = @selector(styleChanged:);
    _wmField.placeholderString = @"Watermark text";
    [_sidebar addSubview:_wmField];
    (void)x; (void)w; (void)y;
}

- (NSTextField *)namedLabel:(NSString *)t tag:(NSInteger)tag {
    NSTextField *f = [self label:t];
    f.tag = tag;
    return f;
}

- (void)buildBottom {
    NSButton *(^btn)(NSString *, SEL) = ^NSButton *(NSString *title, SEL sel) {
        NSButton *b = [NSButton buttonWithTitle:title target:self action:sel];
        b.bezelStyle = NSBezelStyleRounded;
        return b;
    };
    NSButton *copy = btn(@"Copy ⌘C", @selector(copyImage:));
    copy.tag = 1;
    copy.keyEquivalent = @"c";
    copy.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    NSButton *save = btn(@"Save ⌘S", @selector(saveImage:));
    save.tag = 2;
    save.keyEquivalent = @"s";
    save.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    NSButton *saveAs = btn(@"Save As…", @selector(saveAsImage:));
    saveAs.tag = 3;
    NSButton *pin = btn(@"贴图", @selector(pinImage:));
    pin.tag = 5;
    [_bottomBar addSubview:copy];
    [_bottomBar addSubview:save];
    [_bottomBar addSubview:saveAs];
    [_bottomBar addSubview:pin];
    _zoomPopup = [NSPopUpButton new];
    [_zoomPopup addItemsWithTitles:@[@"50%", @"75%", @"100%", @"125%", @"Fit"]];
    [_zoomPopup selectItemWithTitle:@"Fit"];
    _zoomPopup.target = self;
    _zoomPopup.action = @selector(zoomChanged:);
    [_bottomBar addSubview:_zoomPopup];
    NSButton *more = btn(@"More…", @selector(more:));
    more.tag = 4;
    [_bottomBar addSubview:more];
    _hint = [NSTextField labelWithString:@"Double-click to background = Copy and Close"];
    _hint.font = [NSFont systemFontOfSize:11];
    _hint.textColor = NSColor.secondaryLabelColor;
    [_bottomBar addSubview:_hint];
}

- (void)onResize { [self layoutAll]; }

- (void)layoutAll {
    NSView *root = self.window.contentView;
    CGFloat w = root.bounds.size.width, h = root.bounds.size.height;
    CGFloat side = 320, bar = 52;
    _sidebarScroll.frame = NSMakeRect(w - side, 0, side, h);
    _sidebar.frame = NSMakeRect(0, 0, side, 1240);
    _sidebar.layer.backgroundColor = XSSidebar().CGColor;
    _bottomBar.frame = NSMakeRect(0, 0, w - side, bar);
    _canvas.frame = NSMakeRect(0, bar, w - side, h - bar);
    [self layoutSidebar];
    [self layoutBottom];
    [self applyZoom];
}

- (NSView *)sidebarSubviewWithTag:(NSInteger)tag {
    for (NSView *v in _sidebar.subviews) if (v.tag == tag) return v;
    return nil;
}

- (void)layoutSidebar {
    CGFloat x = 14, w = 292, y = 16;
    _presetPopup.frame = NSMakeRect(x, y, w - 32, 24);
    NSView *trash = nil;
    for (NSView *v in _sidebar.subviews) if (v.tag == 9001) trash = v;
    trash.frame = NSMakeRect(x + w - 26, y, 24, 24);
    y += 36;
    [self sidebarSubviewWithTag:100].frame = NSMakeRect(x, y, w, 16); y += 18;
    _padSlider.frame = NSMakeRect(x, y, w, 18); y += 28;
    [self sidebarSubviewWithTag:101].frame = NSMakeRect(x, y, 80, 16);
    _balanceCheck.frame = NSMakeRect(x + 90, y - 2, 120, 20); y += 18;
    _insetSlider.frame = NSMakeRect(x, y, w, 18); y += 28;
    [self sidebarSubviewWithTag:102].frame = NSMakeRect(x, y, w, 16); y += 18;
    _radiusSlider.frame = NSMakeRect(x, y, w, 18); y += 28;
    [self sidebarSubviewWithTag:103].frame = NSMakeRect(x, y, w, 16); y += 18;
    _shadowSlider.frame = NSMakeRect(x, y, w, 18); y += 28;
    [self sidebarSubviewWithTag:106].frame = NSMakeRect(x, y, w, 16); y += 18;
    _blurSlider.frame = NSMakeRect(x, y, w, 18); y += 28;
    [self sidebarSubviewWithTag:104].frame = NSMakeRect(x, y, w, 16); y += 20;
    NSInteger i = 0;
    CGFloat cellW = 54, cellH = 36, gap = 4;
    CGFloat gridTop = y;
    NSInteger bgCount = (NSInteger)_bgButtons.count;
    NSInteger bgRows = (bgCount + 4) / 5;
    for (NSButton *b in _bgButtons) {
        NSInteger col = i % 5, row = i / 5;
        CGFloat bx = x + col * (cellW + gap);
        CGFloat by = gridTop + row * (cellH + 16);
        b.frame = NSMakeRect(bx, by, cellW, cellH);
        NSView *cap = nil;
        NSString *cid = [NSString stringWithFormat:@"cap-%@", b.identifier];
        for (NSView *v in _sidebar.subviews) if ([v.identifier isEqualToString:cid]) cap = v;
        cap.frame = NSMakeRect(bx, by + cellH, cellW, 12);
        i++;
    }
    y = gridTop + bgRows * (cellH + 16) + 8;
    [self sidebarSubviewWithTag:105].frame = NSMakeRect(x, y, w, 16); y += 20;
    i = 0;
    // 2 columns so full names fit (Twitter / Instagram / LinkedIn …)
    CGFloat rw = (w - 8) / 2.0, rh = 26, rg = 8;
    CGFloat ratioTop = y;
    for (NSButton *b in _ratioButtons) {
        NSInteger col = i % 2, row = i / 2;
        b.frame = NSMakeRect(x + col * (rw + rg), ratioTop + row * (rh + 6), rw, rh);
        i++;
    }
    NSInteger ratioRows = (_ratioButtons.count + 1) / 2;
    y = ratioTop + ratioRows * (rh + 6) + 16;
    _redactCheck.frame = NSMakeRect(x, y, w, 20); y += 24;
    _wmCheck.frame = NSMakeRect(x, y, w, 20); y += 26;
    _wmField.frame = NSMakeRect(x, y, w, 24);
}

- (void)layoutBottom {
    CGFloat y = 12;
    CGFloat x = 12;
    for (NSView *v in _bottomBar.subviews) {
        if ([v isKindOfClass:NSButton.class] && ((v.tag >= 1 && v.tag <= 4) || v.tag == 5)) {
            NSButton *b = (NSButton *)v;
            [b sizeToFit];
            NSRect f = b.frame;
            f.origin = NSMakePoint(x, y);
            f.size.height = 28;
            b.frame = f;
            x += f.size.width + 8;
        }
    }
    _zoomPopup.frame = NSMakeRect(x, y, 80, 28);
    [_hint sizeToFit];
    NSRect hf = _hint.frame;
    hf.origin = NSMakePoint(_bottomBar.bounds.size.width - hf.size.width - 16, y + 6);
    _hint.frame = hf;
}

- (void)showWithImage:(NSImage *)image {
    _source = image;
    _emailCount = 0;
    NSApp.activationPolicy = NSApplicationActivationPolicyRegular;
    [self reloadPresetPopup];
    [self syncControlsFromPreset];
    _canvas.rendered = image;
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self layoutAll];
    [self applyZoom];
    [_canvas setNeedsDisplay:YES];
    _copyWhenRendered = YES;
    [self scheduleRerender];
}

- (void)scheduleRerender {
    if (!_source) return;
    NSUInteger token = ++_renderToken;
    NSImage *source = _source;
    XSPreset *preset = [XSPresetStore.shared.current copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSImage *src = source;
        NSInteger emailCount = 0;
        if (preset.redactEmails) {
            src = [XSRedactor redactEmailsInImage:source foundCount:&emailCount];
        }
        NSImage *rendered = [XSImageRenderer renderSource:src preset:preset];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (token != self->_renderToken || source != self->_source) return;
            self->_processed = (src != source) ? src : nil;
            self->_emailCount = emailCount;
            self->_rendered = rendered;
            self->_canvas.rendered = rendered;
            if (preset.redactEmails) {
                self->_redactCheck.title = [NSString stringWithFormat:@"Redact email addresses (found %ld)", (long)emailCount];
            } else {
                self->_redactCheck.title = @"Redact email addresses";
            }
            [self applyZoom];
            [self->_canvas setNeedsDisplay:YES];
            if (self->_copyWhenRendered) {
                self->_copyWhenRendered = NO;
                [self copyImage:nil];
            }
        });
    });
}

- (void)windowWillClose:(NSNotification *)notification {
    NSApp.activationPolicy = NSApplicationActivationPolicyAccessory;
    _renderToken++;
    _source = nil;
    _processed = nil;
    _rendered = nil;
    _canvas.rendered = nil;
    _copyWhenRendered = NO;
    [XSBackgroundCatalog trimCache];
}

- (void)reloadPresetPopup {
    [_presetPopup removeAllItems];
    [_presetPopup addItemWithTitle:XSPresetStore.shared.current.name ?: @"Default"];
    if (XSPresetStore.shared.savedPresets.count) {
        [_presetPopup.menu addItem:NSMenuItem.separatorItem];
        for (XSPreset *p in XSPresetStore.shared.savedPresets) {
            [_presetPopup addItemWithTitle:p.name];
        }
    }
    [_presetPopup.menu addItem:NSMenuItem.separatorItem];
    [_presetPopup addItemWithTitle:@"Save Preset…"];
    [_presetPopup selectItemAtIndex:0];
}

- (void)syncControlsFromPreset {
    _updating = YES;
    XSPreset *p = XSPresetStore.shared.current;
    _padSlider.doubleValue = p.padding;
    _insetSlider.doubleValue = p.inset;
    _radiusSlider.doubleValue = p.borderRadius;
    _shadowSlider.doubleValue = p.shadow;
    _blurSlider.doubleValue = p.backgroundBlur;
    _balanceCheck.state = p.balance ? NSControlStateValueOn : NSControlStateValueOff;
    _redactCheck.state = p.redactEmails ? NSControlStateValueOn : NSControlStateValueOff;
    _wmCheck.state = p.showWatermark ? NSControlStateValueOn : NSControlStateValueOff;
    _wmField.stringValue = p.watermarkText ?: @"";
    for (NSButton *b in _bgButtons) {
        BOOL on = [b.identifier isEqualToString:p.backgroundId];
        b.layer.borderWidth = on ? 2 : 0;
        b.wantsLayer = YES;
        b.layer.borderColor = NSColor.controlAccentColor.CGColor;
        b.layer.cornerRadius = 4;
    }
    for (NSButton *b in _ratioButtons) {
        BOOL on = [b.identifier isEqualToString:p.ratioId];
        b.state = on ? NSControlStateValueOn : NSControlStateValueOff;
        b.bezelColor = on ? NSColor.controlAccentColor : nil;
    }
    _updating = NO;
}

- (void)applyControlsToPreset {
    XSPreset *p = XSPresetStore.shared.current;
    p.padding = _padSlider.doubleValue;
    p.inset = _insetSlider.doubleValue;
    p.borderRadius = _radiusSlider.doubleValue;
    p.shadow = _shadowSlider.doubleValue;
    p.backgroundBlur = _blurSlider.doubleValue;
    p.balance = _balanceCheck.state == NSControlStateValueOn;
    p.redactEmails = _redactCheck.state == NSControlStateValueOn;
    p.showWatermark = _wmCheck.state == NSControlStateValueOn;
    p.watermarkText = _wmField.stringValue;
    [XSPresetStore.shared persistCurrent];
}

- (void)styleChanged:(id)sender {
    if (_updating) return;
    [self applyControlsToPreset];
    [self rerender];
}

- (void)bgClicked:(NSButton *)sender {
    XSPreset *p = XSPresetStore.shared.current;
    p.backgroundId = sender.identifier;
    if ([sender.identifier isEqualToString:@"custom"]) {
        NSColorPanel *panel = NSColorPanel.sharedColorPanel;
        panel.color = p.customColor ?: NSColor.systemBlueColor;
        panel.target = self;
        panel.action = @selector(customColorPicked:);
        [panel orderFront:nil];
    }
    [XSPresetStore.shared persistCurrent];
    [self syncControlsFromPreset];
    [self rerender];
}

- (void)customColorPicked:(NSColorPanel *)panel {
    XSPresetStore.shared.current.customColor = panel.color;
    XSPresetStore.shared.current.backgroundId = @"custom";
    [XSPresetStore.shared persistCurrent];
    [self rerender];
}

- (void)ratioClicked:(NSButton *)sender {
    XSPresetStore.shared.current.ratioId = sender.identifier;
    [XSPresetStore.shared persistCurrent];
    [self rerender];
}

- (void)presetChanged:(NSPopUpButton *)sender {
    NSString *title = sender.titleOfSelectedItem;
    if ([title isEqualToString:@"Save Preset…"]) {
        [self savePresetDialog];
        [self reloadPresetPopup];
        return;
    }
    BOOL isSaved = NO;
    for (XSPreset *p in XSPresetStore.shared.savedPresets) {
        if ([p.name isEqualToString:title]) { isSaved = YES; break; }
    }
    if (isSaved) {
        [XSPresetStore.shared applySavedPresetNamed:title];
        [self syncControlsFromPreset];
        [self rerender];
    }
}

- (void)savePresetDialog {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Save Preset";
    alert.informativeText = @"This look will be reused as a named template.";
    NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
    tf.stringValue = @"Your Preset";
    alert.accessoryView = tf;
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [self applyControlsToPreset];
        [XSPresetStore.shared saveNamedPreset:tf.stringValue];
    }
}

- (void)deletePreset:(id)sender {
    NSString *name = XSPresetStore.shared.current.name;
    [XSPresetStore.shared deletePresetNamed:name];
    [self reloadPresetPopup];
}

- (void)rerender {
    [self scheduleRerender];
}

- (void)applyZoom {
    if (!_rendered) return;
    NSString *t = _zoomPopup.titleOfSelectedItem;
    NSSize sz = _rendered.size;
    if (sz.width < 1 || sz.height < 1) return;
    if ([t isEqualToString:@"Fit"]) {
        NSSize avail = _canvas.bounds.size;
        if (avail.width < 80 || avail.height < 80) return;
        CGFloat z = MIN((avail.width - 48) / sz.width, (avail.height - 48) / sz.height);
        if (!isfinite(z) || z <= 0) z = 1;
        _canvas.zoom = MIN(8.0, MAX(0.12, z));
    } else {
        _canvas.zoom = MAX(0.1, t.doubleValue / 100.0);
    }
    [_canvas setNeedsDisplay:YES];
}

- (void)zoomChanged:(id)sender { [self applyZoom]; }

- (NSData *)pngData {
    if (!_rendered) return nil;
    NSRect proposed = NSMakeRect(0, 0, _rendered.size.width, _rendered.size.height);
    CGImageRef cg = [_rendered CGImageForProposedRect:&proposed context:nil hints:nil];
    if (!cg) return nil;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cg];
    return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

- (void)copyImage:(id)sender {
    if (!_rendered) return;
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb clearContents];
    [pb writeObjects:@[_rendered]];
}

- (void)copyAndClose {
    [self copyImage:nil];
    [self.window close];
}

- (void)pinImage:(id)sender {
    if (!_source) return;
    NSImage *img = _source;
    NSScreen *s = self.window.screen ?: NSScreen.mainScreen;
    NSRect sf = s.visibleFrame;
    NSRect dest = NSMakeRect(sf.origin.x + 40, sf.origin.y + sf.size.height - img.size.height - 80, img.size.width, img.size.height);
    [[XSPinController shared] pinImage:img atScreenRect:dest];
}

- (void)saveImage:(id)sender {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) firstObject];
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"yyyy-MM-dd-HHmmss";
    NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"xShot-%@.png", [fmt stringFromDate:NSDate.date]]];
    [[self pngData] writeToFile:path atomically:YES];
}

- (void)saveAsImage:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[UTTypePNG];
    panel.nameFieldStringValue = @"xShot.png";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r == NSModalResponseOK) [[self pngData] writeToURL:panel.URL atomically:YES];
    }];
}

- (void)share:(id)sender {
    if (!_rendered) return;
    NSSharingServicePicker *picker = [[NSSharingServicePicker alloc] initWithItems:@[_rendered]];
    [picker showRelativeToRect:((NSView *)sender).bounds ofView:sender preferredEdge:NSRectEdgeMinY];
}

- (void)more:(id)sender {
    NSMenu *menu = [NSMenu new];
    [menu addItemWithTitle:@"Open File…" action:@selector(openFile:) keyEquivalent:@"o"].target = self;
    [menu addItemWithTitle:@"Open from Clipboard" action:@selector(openClipboard:) keyEquivalent:@"v"].target = self;
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"Settings…" action:@selector(openSettings:) keyEquivalent:@","].target = self;
    NSButton *b = sender;
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, b.bounds.size.height) inView:b];
}

- (void)openFile:(id)sender {
    NSOpenPanel *p = [NSOpenPanel openPanel];
    p.allowedContentTypes = @[UTTypeImage];
    p.allowsMultipleSelection = NO;
    [p beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r != NSModalResponseOK) return;
        NSImage *img = [[NSImage alloc] initWithContentsOfURL:p.URL];
        if (img) [self showWithImage:img];
    }];
}

- (void)openClipboard:(id)sender {
    NSImage *img = [[NSImage alloc] initWithPasteboard:NSPasteboard.generalPasteboard];
    if (img) [self showWithImage:img];
}

- (void)openSettings:(id)sender {
    [XSSettingsWindowController.shared show];
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 53) { [self.window close]; return; }
    NSEventModifierFlags m = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if ((m & NSEventModifierFlagCommand) && event.keyCode == 8) { [self copyImage:nil]; return; }
    if ((m & NSEventModifierFlagCommand) && event.keyCode == 1) {
        if (m & NSEventModifierFlagShift) [self saveAsImage:nil];
        else [self saveImage:nil];
        return;
    }
    [super keyDown:event];
}

@end
