#import <Cocoa/Cocoa.h>
@class XSPreset;

NS_ASSUME_NONNULL_BEGIN

@interface XSPresetStore : NSObject
@property (nonatomic, strong) XSPreset *current;
@property (nonatomic, copy) NSArray<XSPreset *> *savedPresets;

+ (instancetype)shared;
- (void)persistCurrent;
- (void)saveNamedPreset:(NSString *)name;
- (void)deletePresetNamed:(NSString *)name;
- (void)applySavedPresetNamed:(NSString *)name;
- (void)reload;
@end

NS_ASSUME_NONNULL_END
