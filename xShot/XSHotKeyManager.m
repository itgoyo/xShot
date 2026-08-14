#import "XSHotKeyManager.h"

static const UInt32 kXSHotKeySignature = 'xSht';

@interface XSHotKeyManager ()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *hotKeyRefs;
@property (nonatomic, assign) EventHandlerRef handlerRef;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSDictionary *> *bindings;
@end

static OSStatus XSHotKeyHandler(EventHandlerCallRef next, EventRef event, void *userData) {
    EventHotKeyID hid;
    GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hid), NULL, &hid);
    XSHotKeyManager *mgr = (__bridge XSHotKeyManager *)userData;
    XSHotKeyAction action = (XSHotKeyAction)hid.id;
    dispatch_async(dispatch_get_main_queue(), ^{
        [mgr.delegate hotKeyActionTriggered:action];
    });
    return noErr;
}

@implementation XSHotKeyManager

+ (instancetype)shared {
    static XSHotKeyManager *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [XSHotKeyManager new]; });
    return m;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _hotKeyRefs = [NSMutableDictionary dictionary];
        _bindings = [NSMutableDictionary dictionary];
        [self loadDefaults];
    }
    return self;
}

- (NSString *)keyCodeDefaultsKey:(XSHotKeyAction)a {
    return [NSString stringWithFormat:@"xshot.hotkey.%ld.keyCode", (long)a];
}
- (NSString *)modsDefaultsKey:(XSHotKeyAction)a {
    return [NSString stringWithFormat:@"xshot.hotkey.%ld.modifiers", (long)a];
}

- (void)loadDefaults {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSDictionary *defs = @{
        @(XSHotKeyActionCapture): @{@"key": @(kVK_ANSI_X), @"mods": @(cmdKey | shiftKey)},
        @(XSHotKeyActionPin): @{@"key": @(kVK_ANSI_P), @"mods": @(cmdKey | shiftKey)},
        @(XSHotKeyActionColorPicker): @{@"key": @(kVK_ANSI_C), @"mods": @(cmdKey | shiftKey)},
    };
    // migrate legacy single hotkey
    if ([ud objectForKey:@"xshot.hotkey.keyCode"] && ![ud objectForKey:[self keyCodeDefaultsKey:XSHotKeyActionCapture]]) {
        [ud setInteger:[ud integerForKey:@"xshot.hotkey.keyCode"] forKey:[self keyCodeDefaultsKey:XSHotKeyActionCapture]];
        [ud setInteger:[ud integerForKey:@"xshot.hotkey.modifiers"] forKey:[self modsDefaultsKey:XSHotKeyActionCapture]];
    }
    for (NSNumber *act in defs) {
        XSHotKeyAction a = act.integerValue;
        UInt32 key, mods;
        if ([ud objectForKey:[self keyCodeDefaultsKey:a]]) {
            key = (UInt32)[ud integerForKey:[self keyCodeDefaultsKey:a]];
            mods = (UInt32)[ud integerForKey:[self modsDefaultsKey:a]];
        } else {
            key = [defs[act][@"key"] unsignedIntValue];
            mods = [defs[act][@"mods"] unsignedIntValue];
        }
        self.bindings[act] = @{@"key": @(key), @"mods": @(mods)};
    }
}

- (UInt32)keyCodeForAction:(XSHotKeyAction)action {
    return [self.bindings[@(action)][@"key"] unsignedIntValue];
}
- (UInt32)modifiersForAction:(XSHotKeyAction)action {
    return [self.bindings[@(action)][@"mods"] unsignedIntValue];
}
- (NSString *)displayForAction:(XSHotKeyAction)action {
    return [XSHotKeyManager displayForKeyCode:[self keyCodeForAction:action] modifiers:[self modifiersForAction:action]];
}

+ (NSString *)titleForAction:(XSHotKeyAction)action {
    switch (action) {
        case XSHotKeyActionCapture: return @"截图";
        case XSHotKeyActionPin: return @"贴图";
        case XSHotKeyActionColorPicker: return @"屏幕拾色";
    }
    return @"";
}

- (void)registerAll {
    [self unregisterAll];
    EventTypeSpec spec = { kEventClassKeyboard, kEventHotKeyPressed };
    InstallApplicationEventHandler(XSHotKeyHandler, 1, &spec, (__bridge void *)self, &_handlerRef);
    for (NSNumber *act in self.bindings) {
        XSHotKeyAction a = act.integerValue;
        EventHotKeyID hid = { kXSHotKeySignature, (UInt32)a };
        EventHotKeyRef ref = NULL;
        RegisterEventHotKey([self keyCodeForAction:a], [self modifiersForAction:a], hid, GetApplicationEventTarget(), 0, &ref);
        if (ref) self.hotKeyRefs[act] = [NSValue valueWithPointer:ref];
    }
}

- (void)unregisterAll {
    for (NSValue *v in self.hotKeyRefs.allValues) {
        EventHotKeyRef ref = v.pointerValue;
        if (ref) UnregisterEventHotKey(ref);
    }
    [self.hotKeyRefs removeAllObjects];
    if (_handlerRef) {
        RemoveEventHandler(_handlerRef);
        _handlerRef = NULL;
    }
}

- (void)updateAction:(XSHotKeyAction)action keyCode:(UInt32)keyCode modifiers:(UInt32)modifiers {
    self.bindings[@(action)] = @{@"key": @(keyCode), @"mods": @(modifiers)};
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    [ud setInteger:keyCode forKey:[self keyCodeDefaultsKey:action]];
    [ud setInteger:modifiers forKey:[self modsDefaultsKey:action]];
    [self registerAll];
}

+ (NSString *)displayForKeyCode:(UInt32)keyCode modifiers:(UInt32)modifiers {
    NSMutableString *s = [NSMutableString string];
    if (modifiers & controlKey) [s appendString:@"⌃"];
    if (modifiers & optionKey) [s appendString:@"⌥"];
    if (modifiers & shiftKey) [s appendString:@"⇧"];
    if (modifiers & cmdKey) [s appendString:@"⌘"];
    NSString *key = @"";
    UniCharCount len = 0;
    UniChar chars[4];
    UInt32 dead = 0;
    UCKeyboardLayout *layout = NULL;
    TISInputSourceRef source = TISCopyCurrentKeyboardLayoutInputSource();
    if (source) {
        CFDataRef data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData);
        if (data) layout = (UCKeyboardLayout *)CFDataGetBytePtr(data);
        if (layout) {
            UCKeyTranslate(layout, (UInt16)keyCode, kUCKeyActionDisplay, 0, LMGetKbdType(), kUCKeyTranslateNoDeadKeysBit, &dead, 4, &len, chars);
            if (len > 0) key = [[NSString stringWithCharacters:chars length:len] uppercaseString];
        }
        CFRelease(source);
    }
    if (key.length == 0) {
        static NSDictionary *special;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            special = @{
                @(kVK_Return): @"↩", @(kVK_Space): @"Space", @(kVK_Tab): @"⇥",
                @(kVK_Delete): @"⌫", @(kVK_Escape): @"⎋",
                @(kVK_F1): @"F1", @(kVK_F2): @"F2", @(kVK_F3): @"F3", @(kVK_F4): @"F4",
                @(kVK_LeftArrow): @"←", @(kVK_RightArrow): @"→", @(kVK_UpArrow): @"↑", @(kVK_DownArrow): @"↓",
            };
        });
        key = special[@(keyCode)] ?: [NSString stringWithFormat:@"#%u", keyCode];
    }
    [s appendString:key];
    return s;
}

@end
