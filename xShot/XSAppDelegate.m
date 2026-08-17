#import <Cocoa/Cocoa.h>
#import "XSAppDelegate.h"
#import "XSHotKeyManager.h"
#import "XSCaptureController.h"
#import "XSSettingsWindowController.h"
#import "XSEditorWindowController.h"
#import "XSColorPickerController.h"
#import "XSPresetStore.h"
#import "XSPinController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface XSAppDelegate () <XSHotKeyManagerDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@end

@implementation XSAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)XSPresetStore.shared;
    XSHotKeyManager.shared.delegate = self;
    [XSHotKeyManager.shared registerAll];
    [self setupStatusItem];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setupStatusItem) name:@"xshot.hotkey.changed" object:nil];
    if (!CGPreflightScreenCaptureAccess()) {
        CGRequestScreenCaptureAccess();
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [XSEditorWindowController prewarm];
    });
}

- (void)setupStatusItem {
    if (!self.statusItem) {
        self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
        NSImage *img = [NSImage imageWithSystemSymbolName:@"camera.viewfinder" accessibilityDescription:@"xShot"];
        img.template = YES;
        self.statusItem.button.image = img;
    }
    NSMenu *menu = [NSMenu new];
    NSString *plain = [NSString stringWithFormat:@"普通截图    %@", [XSHotKeyManager.shared displayForAction:XSHotKeyActionPlainCapture]];
    NSString *cap = [NSString stringWithFormat:@"美化截图    %@", [XSHotKeyManager.shared displayForAction:XSHotKeyActionCapture]];
    NSString *pick = [NSString stringWithFormat:@"屏幕拾色    %@", [XSHotKeyManager.shared displayForAction:XSHotKeyActionColorPicker]];
    NSString *pin = [NSString stringWithFormat:@"贴图    %@", [XSHotKeyManager.shared displayForAction:XSHotKeyActionPin]];
    [menu addItemWithTitle:plain action:@selector(plainCapture:) keyEquivalent:@""].target = self;
    [menu addItemWithTitle:cap action:@selector(capture:) keyEquivalent:@""].target = self;
    [menu addItemWithTitle:pick action:@selector(colorPick:) keyEquivalent:@""].target = self;
    [menu addItemWithTitle:pin action:@selector(pin:) keyEquivalent:@""].target = self;
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"从剪贴板打开" action:@selector(openClipboard:) keyEquivalent:@""].target = self;
    [menu addItemWithTitle:@"打开文件…" action:@selector(openFile:) keyEquivalent:@""].target = self;
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"设置…" action:@selector(settings:) keyEquivalent:@","].target = self;
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"退出 xShot" action:@selector(quit:) keyEquivalent:@"q"].target = self;
    self.statusItem.menu = menu;
}

- (void)hotKeyActionTriggered:(XSHotKeyAction)action {
    switch (action) {
        case XSHotKeyActionCapture: [XSCaptureController.shared beginCapture]; break;
        case XSHotKeyActionPlainCapture: [XSCaptureController.shared beginPlainCapture]; break;
        case XSHotKeyActionPin: [[XSPinController shared] pinClipboardIfImage]; break;
        case XSHotKeyActionColorPicker: [XSColorPickerController.shared beginPick]; break;
    }
}

- (void)capture:(id)sender { [XSCaptureController.shared beginCapture]; }
- (void)plainCapture:(id)sender { [XSCaptureController.shared beginPlainCapture]; }
- (void)pin:(id)sender { [[XSPinController shared] pinClipboardIfImage]; }
- (void)colorPick:(id)sender { [XSColorPickerController.shared beginPick]; }

- (void)openClipboard:(id)sender {
    NSImage *img = [[NSImage alloc] initWithPasteboard:NSPasteboard.generalPasteboard];
    if (img) [[XSEditorWindowController shared] showWithImage:img];
}

- (void)openFile:(id)sender {
    NSOpenPanel *p = [NSOpenPanel openPanel];
    p.allowedContentTypes = @[UTTypeImage];
    if ([p runModal] == NSModalResponseOK) {
        NSImage *img = [[NSImage alloc] initWithContentsOfURL:p.URL];
        if (img) [[XSEditorWindowController shared] showWithImage:img];
    }
}

- (void)settings:(id)sender {
    [XSSettingsWindowController.shared show];
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app { return YES; }

@end
