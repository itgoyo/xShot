#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 编辑器画布、窗口与设置页的底色：浅色模式保持原来的奶油纸张色，
/// 深色模式换成同色相的暖深灰，避免白字压白底。
FOUNDATION_EXPORT NSColor *XSThemeCanvasColor(void);

/// 编辑器侧栏底色，深色模式下比画布略亮一档，保留层次。
FOUNDATION_EXPORT NSColor *XSThemeSidebarColor(void);

/// 设置页卡片底色。
FOUNDATION_EXPORT NSColor *XSThemeCardColor(void);

/// 设置页图标底色：浅色模式沿用传入的浅色，深色模式压暗成同色相的深色块。
FOUNDATION_EXPORT NSColor *XSThemeTileColor(NSColor *lightColor);

/// 图标前景色：浅色模式沿用传入的颜色，深色模式提亮，保证压在深色块上仍清晰。
FOUNDATION_EXPORT NSColor *XSThemeTintColor(NSColor *lightColor);

/// 编辑器「无背景」时的棋盘格，alternate 取交错色。
FOUNDATION_EXPORT NSColor *XSThemeCheckerColor(BOOL alternate);

/// 把动态色在指定外观下解析成静态色，供 CALayer 等只能存 CGColor 的位置使用。
FOUNDATION_EXPORT NSColor *XSThemeResolvedColor(NSColor *color, NSAppearance *appearance);

/// 解析后再加透明度。注意不能先 colorWithAlphaComponent: 再解析，
/// 那会把动态色冻结成调用时刻的外观（深色模式下仍取到浅色）。
FOUNDATION_EXPORT NSColor *XSThemeResolvedAlphaColor(NSColor *color, CGFloat alpha, NSAppearance *appearance);

/// 铺满窗口 content 的底色视图：外观切换时重绘，并同步窗口背景（标题栏透明时也一致）。
@interface XSThemeBackgroundView : NSView
@end

NS_ASSUME_NONNULL_END
