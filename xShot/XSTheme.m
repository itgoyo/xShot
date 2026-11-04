#import "XSTheme.h"
#import <dispatch/dispatch.h>

static BOOL XSIsDarkAppearance(NSAppearance *appearance) {
    NSAppearanceName best = [appearance bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameAqua,
        NSAppearanceNameDarkAqua,
    ]];
    return [best isEqualToString:NSAppearanceNameDarkAqua];
}

/// 包装一个随外观动态解析的颜色。AppKit 在绘制时会用当前外观回调 block。
static NSColor *XSDynamicColor(NSColor * (^resolve)(BOOL dark)) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        return resolve(XSIsDarkAppearance(appearance));
    }];
}

NSColor *XSThemeCanvasColor(void) {
    static NSColor *color;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        color = XSDynamicColor(^NSColor *(BOOL dark) {
            if (dark) return [NSColor colorWithCalibratedRed:0.110 green:0.106 blue:0.098 alpha:1];
            return [NSColor colorWithCalibratedRed:0.965 green:0.957 blue:0.941 alpha:1];
        });
    });
    return color;
}

NSColor *XSThemeSidebarColor(void) {
    static NSColor *color;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        color = XSDynamicColor(^NSColor *(BOOL dark) {
            if (dark) return [NSColor colorWithCalibratedRed:0.153 green:0.147 blue:0.137 alpha:1];
            return [NSColor colorWithCalibratedRed:0.925 green:0.918 blue:0.902 alpha:1];
        });
    });
    return color;
}

NSColor *XSThemeCardColor(void) {
    static NSColor *color;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        color = XSDynamicColor(^NSColor *(BOOL dark) {
            if (dark) return [NSColor colorWithCalibratedRed:0.176 green:0.169 blue:0.157 alpha:1];
            return [NSColor whiteColor];
        });
    });
    return color;
}

NSColor *XSThemeTileColor(NSColor *lightColor) {
    return XSDynamicColor(^NSColor *(BOOL dark) {
        if (!dark) return lightColor;
        return [lightColor blendedColorWithFraction:0.70 ofColor:[NSColor blackColor]] ?: lightColor;
    });
}

NSColor *XSThemeTintColor(NSColor *lightColor) {
    return XSDynamicColor(^NSColor *(BOOL dark) {
        if (!dark) return lightColor;
        return [lightColor blendedColorWithFraction:0.45 ofColor:[NSColor whiteColor]] ?: lightColor;
    });
}

NSColor *XSThemeCheckerColor(BOOL alternate) {
    return XSDynamicColor(^NSColor *(BOOL dark) {
        CGFloat white;
        if (dark) white = alternate ? 0.13 : 0.19;
        else white = alternate ? 0.80 : 0.92;
        return [NSColor colorWithCalibratedWhite:white alpha:1];
    });
}

NSColor *XSThemeResolvedColor(NSColor *color, NSAppearance *appearance) {
    if (!color || !appearance) return color;
    __block NSColor *resolved = color;
    [appearance performAsCurrentDrawingAppearance:^{
        NSColor *srgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        if (srgb) resolved = srgb;
    }];
    return resolved;
}

NSColor *XSThemeResolvedAlphaColor(NSColor *color, CGFloat alpha, NSAppearance *appearance) {
    return [XSThemeResolvedColor(color, appearance) colorWithAlphaComponent:alpha];
}

@implementation XSThemeBackgroundView
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    [XSThemeCanvasColor() setFill];
    NSRectFill(self.bounds);
}
- (void)syncWindowBackground {
    NSWindow *window = self.window;
    if (window) {
        window.backgroundColor = XSThemeResolvedColor(XSThemeCanvasColor(), self.effectiveAppearance);
    }
}
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self syncWindowBackground];
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self setNeedsDisplay:YES];
    [self syncWindowBackground];
}
@end
