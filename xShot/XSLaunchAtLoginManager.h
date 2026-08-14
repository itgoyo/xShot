#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface XSLaunchAtLoginManager : NSObject
+ (instancetype)shared;
- (BOOL)isEnabled;
- (BOOL)setEnabled:(BOOL)enabled error:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
