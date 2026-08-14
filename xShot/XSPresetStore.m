#import "XSPresetStore.h"
#import "XSPreset.h"

static NSString * const kXSCurrentKey = @"xshot.currentPreset";
static NSString * const kXSSavedKey = @"xshot.savedPresets";

@implementation XSPresetStore

+ (instancetype)shared {
    static XSPresetStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [XSPresetStore new]; });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) [self reload];
    return self;
}

- (void)reload {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSDictionary *cur = [ud dictionaryForKey:kXSCurrentKey];
    self.current = cur ? [XSPreset fromDictionary:cur] : [XSPreset defaultPreset];
    NSArray *saved = [ud arrayForKey:kXSSavedKey];
    NSMutableArray *arr = [NSMutableArray array];
    for (NSDictionary *d in saved) {
        if ([d isKindOfClass:NSDictionary.class]) [arr addObject:[XSPreset fromDictionary:d]];
    }
    self.savedPresets = arr;
}

- (void)persistCurrent {
    [NSUserDefaults.standardUserDefaults setObject:[self.current toDictionary] forKey:kXSCurrentKey];
}

- (void)persistSaved {
    NSMutableArray *arr = [NSMutableArray array];
    for (XSPreset *p in self.savedPresets) [arr addObject:[p toDictionary]];
    [NSUserDefaults.standardUserDefaults setObject:arr forKey:kXSSavedKey];
}

- (void)saveNamedPreset:(NSString *)name {
    if (name.length == 0) return;
    XSPreset *p = [self.current copy];
    p.name = name;
    NSMutableArray *arr = [self.savedPresets mutableCopy] ?: [NSMutableArray array];
    NSInteger idx = [arr indexOfObjectPassingTest:^BOOL(XSPreset *obj, NSUInteger i, BOOL *stop) {
        return [obj.name isEqualToString:name];
    }];
    if (idx != NSNotFound) arr[idx] = p;
    else [arr addObject:p];
    self.savedPresets = arr;
    self.current.name = name;
    [self persistSaved];
    [self persistCurrent];
}

- (void)deletePresetNamed:(NSString *)name {
    NSMutableArray *arr = [self.savedPresets mutableCopy];
    [arr filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(XSPreset *p, NSDictionary *b) {
        return ![p.name isEqualToString:name];
    }]];
    self.savedPresets = arr;
    [self persistSaved];
}

- (void)applySavedPresetNamed:(NSString *)name {
    for (XSPreset *p in self.savedPresets) {
        if ([p.name isEqualToString:name]) {
            self.current = [p copy];
            [self persistCurrent];
            return;
        }
    }
}

@end
