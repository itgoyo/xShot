#import <Cocoa/Cocoa.h>
@class XSPreset;

NS_ASSUME_NONNULL_BEGIN

@interface XSImageRenderer : NSObject
+ (void)warmup;
+ (NSColor *)detectBackgroundColor:(NSImage *)image;
+ (NSImage *)renderSource:(NSImage *)source preset:(XSPreset *)preset;
+ (CGFloat)aspectForRatioId:(NSString *)ratioId;
@end

NS_ASSUME_NONNULL_END
