#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface XSRedactor : NSObject
+ (NSImage *)redactEmailsInImage:(NSImage *)image foundCount:(NSInteger *)count;
@end

NS_ASSUME_NONNULL_END
