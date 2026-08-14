#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface XSCaptureController : NSObject
+ (instancetype)shared;
- (void)beginCapture;
@end

NS_ASSUME_NONNULL_END
