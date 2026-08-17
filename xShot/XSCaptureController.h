#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface XSCaptureController : NSObject
+ (instancetype)shared;
/// 美化截图：进入编辑器并套背景模板
- (void)beginCapture;
/// 普通截图：框选后直接复制原图到剪贴板，不打开编辑器
- (void)beginPlainCapture;
@end

NS_ASSUME_NONNULL_END
