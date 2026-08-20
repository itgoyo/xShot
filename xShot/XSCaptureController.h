#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface XSCaptureController : NSObject
+ (instancetype)shared;
/// 美化截图：进入编辑器并套背景模板
- (void)beginCapture;
/// 普通截图：框选后可调整选区，点打勾才复制原图
- (void)beginPlainCapture;
/// 标注截图：框选后进入标注编辑器
- (void)beginAnnotateCapture;
@end

NS_ASSUME_NONNULL_END
