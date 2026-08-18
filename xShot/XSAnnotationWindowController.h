#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface XSAnnotationWindowController : NSWindowController
+ (instancetype)shared;
- (void)showWithImage:(NSImage *)image;
@end

NS_ASSUME_NONNULL_END
