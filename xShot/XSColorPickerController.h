#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface XSColorPickerController : NSObject
+ (instancetype)shared;
- (void)beginPick;
@end

NS_ASSUME_NONNULL_END
