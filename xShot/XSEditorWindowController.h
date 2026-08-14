#import <Cocoa/Cocoa.h>
@class XSPreset;

NS_ASSUME_NONNULL_BEGIN

@interface XSEditorWindowController : NSWindowController
+ (instancetype)shared;
+ (void)prewarm;
- (void)showWithImage:(NSImage *)image;
@end

NS_ASSUME_NONNULL_END
