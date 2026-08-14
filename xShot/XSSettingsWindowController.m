#import "XSSettingsWindowController.h"
#import "XSHotKeyManager.h"
#import "XSLaunchAtLoginManager.h"
#import <Carbon/Carbon.h>

static NSColor *XSSettingsBg(void) {
    return [NSColor colorWithCalibratedRed:0.965 green:0.957 blue:0.941 alpha:1];
}
static NSColor *XSCardFill(void) {
    if (@available(macOS 10.14, *)) {
        return [NSColor colorNamed:@"controlBackgroundColor"] ?: NSColor.controlBackgroundColor;
    }
    return NSColor.controlBackgroundColor;
}

@interface XSFlippedSettingsView : NSView
@end
@implementation XSFlippedSettingsView
- (BOOL)isFlipped { return YES; }
@end

@interface XSSectionCard : NSView
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) XSFlippedSettingsView *content;
- (instancetype)initWithTitle:(NSString *)title width:(CGFloat)width;
- (void)addRow:(NSView *)row height:(CGFloat)height;
@end

@implementation XSSectionCard {
    CGFloat _contentY;
}
- (instancetype)initWithTitle:(NSString *)title width:(CGFloat)width {
    self = [super initWithFrame:NSMakeRect(0, 0, width, 10)];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 12;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [NSColor.separatorColor colorWithAlphaComponent:0.45].CGColor;
        self.layer.backgroundColor = XSCardFill().CGColor;

        _titleLabel = [NSTextField labelWithString:title];
        _titleLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
        _titleLabel.textColor = NSColor.secondaryLabelColor;
        _titleLabel.frame = NSMakeRect(16, 14, width - 32, 16);
        [self addSubview:_titleLabel];

        _content = [[XSFlippedSettingsView alloc] initWithFrame:NSMakeRect(0, 36, width, 0)];
        _contentY = 0;
        [self addSubview:_content];
    }
    return self;
}
- (void)addRow:(NSView *)row height:(CGFloat)height {
    row.frame = NSMakeRect(0, _contentY, _content.bounds.size.width, height);
    [_content addSubview:row];
    _contentY += height;
    _content.frame = NSMakeRect(0, 36, self.bounds.size.width, _contentY);
    self.frame = NSMakeRect(self.frame.origin.x, self.frame.origin.y, self.bounds.size.width, 36 + _contentY + 8);
}
@end

@interface XSHotKeyField : NSView
@property (nonatomic, assign) XSHotKeyAction action;
@property (nonatomic, copy) void (^onChange)(XSHotKeyAction action, UInt32 keyCode, UInt32 modifiers);
@property (nonatomic, assign) BOOL recording;
- (void)refresh;
@end

@implementation XSHotKeyField {
    NSTextField *_label;
}
- (instancetype)initWithFrame:(NSRect)frame action:(XSHotKeyAction)action {
    self = [super initWithFrame:frame];
    if (self) {
        _action = action;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 8;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [NSColor.separatorColor colorWithAlphaComponent:0.6].CGColor;
        self.layer.backgroundColor = [[NSColor controlBackgroundColor] colorWithAlphaComponent:0.65].CGColor;

        _label = [[NSTextField alloc] initWithFrame:self.bounds];
        _label.editable = NO;
        _label.bordered = NO;
        _label.drawsBackground = NO;
        _label.selectable = NO;
        _label.alignment = NSTextAlignmentCenter;
        _label.font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightMedium];
        _label.stringValue = [XSHotKeyManager.shared displayForAction:action];
        _label.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _label.cell.usesSingleLineMode = YES;
        ((NSCell *)_label.cell).alignment = NSTextAlignmentCenter;
        [self addSubview:_label];
        [self layoutLabel];
    }
    return self;
}
- (void)layoutLabel {
    [_label sizeToFit];
    NSRect b = self.bounds;
    NSRect f = _label.frame;
    f.size.width = MIN(f.size.width + 12, b.size.width - 12);
    f.origin.x = (b.size.width - f.size.width) / 2.0;
    f.origin.y = (b.size.height - f.size.height) / 2.0;
    _label.frame = f;
}
- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    [self layoutLabel];
}
- (BOOL)acceptsFirstResponder { return YES; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *a in self.trackingAreas) [self removeTrackingArea:a];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
                                                       options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                         owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent *)event {
    if (!self.recording) {
        self.layer.backgroundColor = [[NSColor controlAccentColor] colorWithAlphaComponent:0.08].CGColor;
    }
}
- (void)mouseExited:(NSEvent *)event {
    if (!self.recording) {
        self.layer.backgroundColor = [[NSColor controlBackgroundColor] colorWithAlphaComponent:0.65].CGColor;
    }
}
- (void)mouseDown:(NSEvent *)event {
    self.recording = YES;
    self.layer.borderColor = NSColor.controlAccentColor.CGColor;
    self.layer.backgroundColor = [[NSColor controlAccentColor] colorWithAlphaComponent:0.12].CGColor;
    _label.stringValue = @"按下快捷键…";
    _label.textColor = NSColor.controlAccentColor;
    [self layoutLabel];
    [self.window makeFirstResponder:self];
}
- (void)keyDown:(NSEvent *)event {
    if (!self.recording) return;
    if (event.keyCode == 53) {
        self.recording = NO;
        self.layer.borderColor = [NSColor.separatorColor colorWithAlphaComponent:0.6].CGColor;
        self.layer.backgroundColor = [[NSColor controlBackgroundColor] colorWithAlphaComponent:0.65].CGColor;
        _label.textColor = NSColor.labelColor;
        [self refresh];
        return;
    }
    UInt32 mods = 0;
    if (event.modifierFlags & NSEventModifierFlagCommand) mods |= cmdKey;
    if (event.modifierFlags & NSEventModifierFlagShift) mods |= shiftKey;
    if (event.modifierFlags & NSEventModifierFlagOption) mods |= optionKey;
    if (event.modifierFlags & NSEventModifierFlagControl) mods |= controlKey;
    if (mods == 0) return;
    self.recording = NO;
    self.layer.borderColor = [NSColor.separatorColor colorWithAlphaComponent:0.6].CGColor;
    self.layer.backgroundColor = [[NSColor controlBackgroundColor] colorWithAlphaComponent:0.65].CGColor;
    _label.textColor = NSColor.labelColor;
    if (self.onChange) self.onChange(self.action, (UInt32)event.keyCode, mods);
    _label.stringValue = [XSHotKeyManager displayForKeyCode:(UInt32)event.keyCode modifiers:mods];
    [self layoutLabel];
}
- (void)refresh {
    _label.stringValue = [XSHotKeyManager.shared displayForAction:self.action];
    _label.textColor = NSColor.labelColor;
    [self layoutLabel];
}
@end

@interface XSHotKeyRowView : NSView
@property (nonatomic, strong) XSHotKeyField *field;
- (instancetype)initWithAction:(XSHotKeyAction)action width:(CGFloat)width onChange:(void (^)(XSHotKeyAction, UInt32, UInt32))onChange;
@end

@implementation XSHotKeyRowView
- (instancetype)initWithAction:(XSHotKeyAction)action width:(CGFloat)width onChange:(void (^)(XSHotKeyAction, UInt32, UInt32))onChange {
    self = [super initWithFrame:NSMakeRect(0, 0, width, 64)];
    if (self) {
        NSView *iconWrap = [[NSView alloc] initWithFrame:NSMakeRect(16, 14, 36, 36)];
        iconWrap.wantsLayer = YES;
        iconWrap.layer.cornerRadius = 10;
        if (action == XSHotKeyActionColorPicker) {
            iconWrap.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.95 green:0.93 blue:1.0 alpha:1].CGColor;
            NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(6, 6, 24, 24)];
            NSImage *img = [NSImage imageWithSystemSymbolName:@"eyedropper.halffull" accessibilityDescription:nil];
            iv.image = img;
            iv.contentTintColor = [NSColor colorWithCalibratedRed:0.45 green:0.35 blue:0.95 alpha:1];
            [iconWrap addSubview:iv];
            // color dots
            NSArray *colors = @[
                [NSColor colorWithCalibratedRed:0.95 green:0.35 blue:0.35 alpha:1],
                [NSColor colorWithCalibratedRed:0.35 green:0.75 blue:0.45 alpha:1],
                [NSColor colorWithCalibratedRed:0.35 green:0.55 blue:0.95 alpha:1],
            ];
            for (NSUInteger i = 0; i < colors.count; i++) {
                NSView *dot = [[NSView alloc] initWithFrame:NSMakeRect(26 + i * 7, 4 + i * 2, 6, 6)];
                dot.wantsLayer = YES;
                dot.layer.cornerRadius = 3;
                dot.layer.backgroundColor = [colors[i] CGColor];
                dot.layer.borderWidth = 1;
                dot.layer.borderColor = NSColor.whiteColor.CGColor;
                [iconWrap addSubview:dot];
            }
        } else if (action == XSHotKeyActionPin) {
            iconWrap.layer.backgroundColor = [NSColor colorWithCalibratedRed:1.0 green:0.96 blue:0.88 alpha:1].CGColor;
            NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(6, 6, 24, 24)];
            iv.image = [NSImage imageWithSystemSymbolName:@"pin.fill" accessibilityDescription:nil];
            iv.contentTintColor = [NSColor colorWithCalibratedRed:0.85 green:0.55 blue:0.15 alpha:1];
            [iconWrap addSubview:iv];
        } else {
            iconWrap.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.90 green:0.95 blue:1.0 alpha:1].CGColor;
            NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(6, 6, 24, 24)];
            iv.image = [NSImage imageWithSystemSymbolName:@"camera.viewfinder" accessibilityDescription:nil];
            iv.contentTintColor = NSColor.controlAccentColor;
            [iconWrap addSubview:iv];
        }
        [self addSubview:iconWrap];

        NSTextField *title = [NSTextField labelWithString:[XSHotKeyManager titleForAction:action]];
        title.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
        title.frame = NSMakeRect(64, 14, 160, 20);
        [self addSubview:title];

        NSString *subtitle = @"";
        switch (action) {
            case XSHotKeyActionCapture: subtitle = @"框选或窗口截图"; break;
            case XSHotKeyActionPin: subtitle = @"贴剪贴板中的图片"; break;
            case XSHotKeyActionColorPicker: subtitle = @"点击复制 #RRGGBB 色值"; break;
        }
        NSTextField *sub = [NSTextField labelWithString:subtitle];
        sub.font = [NSFont systemFontOfSize:11];
        sub.textColor = NSColor.secondaryLabelColor;
        sub.frame = NSMakeRect(64, 34, 200, 16);
        [self addSubview:sub];

        _field = [[XSHotKeyField alloc] initWithFrame:NSMakeRect(width - 156, 16, 140, 32) action:action];
        _field.onChange = onChange;
        [self addSubview:_field];

        if (action != XSHotKeyActionColorPicker) {
            NSView *sep = [[NSView alloc] initWithFrame:NSMakeRect(64, 63, width - 80, 1)];
            sep.wantsLayer = YES;
            sep.layer.backgroundColor = [NSColor.separatorColor colorWithAlphaComponent:0.35].CGColor;
            [self addSubview:sep];
        }
    }
    return self;
}
@end

@implementation XSSettingsWindowController {
    NSMutableArray<XSHotKeyField *> *_fields;
    NSScrollView *_scroll;
    XSFlippedSettingsView *_content;
    NSButton *_launchSwitch;
}

+ (instancetype)shared {
    static XSSettingsWindowController *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [[XSSettingsWindowController alloc] init]; });
    return c;
}

- (instancetype)init {
    NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 560)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                  backing:NSBackingStoreBuffered defer:NO];
    win.title = @"xShot 设置";
    win.releasedWhenClosed = NO;
    win.backgroundColor = XSSettingsBg();
    if (@available(macOS 10.14, *)) {
        win.titleVisibility = NSWindowTitleHidden;
        win.titlebarAppearsTransparent = YES;
    }
    self = [super initWithWindow:win];
    if (self) [self build];
    return self;
}

- (void)build {
    NSView *root = self.window.contentView;
    root.wantsLayer = YES;
    root.layer.backgroundColor = XSSettingsBg().CGColor;
    _fields = [NSMutableArray array];

    // header
    NSImageView *appIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(24, root.bounds.size.height - 72, 40, 40)];
    appIcon.image = [NSImage imageNamed:@"AppIcon"];
    if (!appIcon.image) {
        appIcon.image = [NSImage imageWithSystemSymbolName:@"camera.viewfinder" accessibilityDescription:nil];
        appIcon.contentTintColor = NSColor.controlAccentColor;
    }
    appIcon.imageScaling = NSImageScaleProportionallyUpOrDown;
    appIcon.autoresizingMask = NSViewMinYMargin;
    [root addSubview:appIcon];

    NSTextField *headerTitle = [NSTextField labelWithString:@"xShot 设置"];
    headerTitle.font = [NSFont systemFontOfSize:22 weight:NSFontWeightBold];
    headerTitle.frame = NSMakeRect(72, root.bounds.size.height - 58, 200, 28);
    headerTitle.autoresizingMask = NSViewMinYMargin;
    [root addSubview:headerTitle];

    NSTextField *headerSub = [NSTextField labelWithString:@"快捷键、启动项与偏好"];
    headerSub.font = [NSFont systemFontOfSize:12];
    headerSub.textColor = NSColor.secondaryLabelColor;
    headerSub.frame = NSMakeRect(72, root.bounds.size.height - 74, 260, 16);
    headerSub.autoresizingMask = NSViewMinYMargin;
    [root addSubview:headerSub];

    _scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 480, root.bounds.size.height - 88)];
    _scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _scroll.drawsBackground = NO;
    _scroll.hasVerticalScroller = YES;
    _scroll.autohidesScrollers = YES;
    _scroll.borderType = NSNoBorder;
    _content = [[XSFlippedSettingsView alloc] initWithFrame:NSMakeRect(0, 0, 480, 10)];
    _scroll.documentView = _content;
    [root addSubview:_scroll];

    CGFloat cardW = 432;
    CGFloat y = 16;

    // General section
    XSSectionCard *general = [[XSSectionCard alloc] initWithTitle:@"通用" width:cardW];
    NSView *launchRow = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, cardW, 56)];
    NSTextField *launchTitle = [NSTextField labelWithString:@"开机自启动"];
    launchTitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    launchTitle.frame = NSMakeRect(16, 12, 120, 20);
    [launchRow addSubview:launchTitle];
    NSTextField *launchSub = [NSTextField labelWithString:@"登录 macOS 后自动运行 xShot"];
    launchSub.font = [NSFont systemFontOfSize:11];
    launchSub.textColor = NSColor.secondaryLabelColor;
    launchSub.frame = NSMakeRect(16, 32, 260, 16);
    [launchRow addSubview:launchSub];
    _launchSwitch = [NSButton checkboxWithTitle:@"" target:self action:@selector(launchAtLoginChanged:)];
    _launchSwitch.buttonType = NSButtonTypeSwitch;
    _launchSwitch.frame = NSMakeRect(cardW - 68, 18, 52, 24);
    _launchSwitch.state = [XSLaunchAtLoginManager.shared isEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    [launchRow addSubview:_launchSwitch];
    [general addRow:launchRow height:56];
    general.frame = NSMakeRect(24, y, cardW, general.frame.size.height);
    [_content addSubview:general];
    y += general.frame.size.height + 16;

    // Hotkeys section
    XSSectionCard *hotkeys = [[XSSectionCard alloc] initWithTitle:@"快捷键" width:cardW];
    NSTextField *hint = [NSTextField wrappingLabelWithString:@"点击右侧快捷键框后按下新的组合键，Esc 取消。"];
    hint.font = [NSFont systemFontOfSize:11];
    hint.textColor = NSColor.secondaryLabelColor;
    hint.frame = NSMakeRect(16, 0, cardW - 32, 32);
    NSView *hintRow = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, cardW, 36)];
    [hintRow addSubview:hint];
    [hotkeys addRow:hintRow height:36];

    NSArray *actions = @[@(XSHotKeyActionCapture), @(XSHotKeyActionPin), @(XSHotKeyActionColorPicker)];
    for (NSNumber *n in actions) {
        XSHotKeyAction a = n.integerValue;
        XSHotKeyRowView *row = [[XSHotKeyRowView alloc] initWithAction:a width:cardW onChange:^(XSHotKeyAction action, UInt32 keyCode, UInt32 modifiers) {
            [XSHotKeyManager.shared updateAction:action keyCode:keyCode modifiers:modifiers];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"xshot.hotkey.changed" object:nil];
        }];
        [hotkeys addRow:row height:64];
        [_fields addObject:row.field];
    }
    hotkeys.frame = NSMakeRect(24, y, cardW, hotkeys.frame.size.height);
    [_content addSubview:hotkeys];
    y += hotkeys.frame.size.height + 16;

    // About section
    XSSectionCard *about = [[XSSectionCard alloc] initWithTitle:@"说明" width:cardW];
    NSTextField *note = [NSTextField wrappingLabelWithString:@"编辑器里改过的样式会自动保存，下次截图默认沿用同一套模板。截图时 Space 切窗口模式，Esc 取消。贴图读取剪贴板图片，可拖动，点 ✕ 关闭。"];
    note.font = [NSFont systemFontOfSize:11];
    note.textColor = NSColor.secondaryLabelColor;
    note.frame = NSMakeRect(16, 0, cardW - 32, 52);
    NSView *noteRow = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, cardW, 60)];
    [noteRow addSubview:note];
    [about addRow:noteRow height:60];
    about.frame = NSMakeRect(24, y, cardW, about.frame.size.height);
    [_content addSubview:about];
    y += about.frame.size.height + 24;

    _content.frame = NSMakeRect(0, 0, 480, y);
}

- (void)launchAtLoginChanged:(NSButton *)sender {
    BOOL on = sender.state == NSControlStateValueOn;
    NSError *err = nil;
    if (![XSLaunchAtLoginManager.shared setEnabled:on error:&err]) {
        sender.state = on ? NSControlStateValueOff : NSControlStateValueOn;
        NSAlert *a = [NSAlert new];
        a.messageText = @"无法设置开机自启动";
        a.informativeText = err.localizedDescription ?: @"请稍后重试。";
        [a runModal];
    }
}

- (void)show {
    for (XSHotKeyField *f in _fields) [f refresh];
    _launchSwitch.state = [XSLaunchAtLoginManager.shared isEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

@end
