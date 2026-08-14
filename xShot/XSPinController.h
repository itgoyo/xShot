#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface XSPinController : NSObject
+ (instancetype)shared;
- (void)pinImage:(NSImage *)image atScreenRect:(NSRect)screenRect;
- (void)pinClipboardIfImage;
- (void)closeAll;
@end

NS_ASSUME_NONNULL_END
