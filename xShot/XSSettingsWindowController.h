#import <Cocoa/Cocoa.h>
#import "XSHotKeyManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface XSSettingsWindowController : NSWindowController
+ (instancetype)shared;
- (void)show;
@end

NS_ASSUME_NONNULL_END
