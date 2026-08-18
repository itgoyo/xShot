#import "XSAnnotationWindowController.h"
#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

typedef NS_ENUM(NSInteger, XSATool) {
    XSAToolArrow = 0,
    XSAToolRect,
    XSAToolEllipse,
    XSAToolPen,
    XSAToolText,
    XSAToolMosaic,
};

@interface XSAnnotation : NSObject
@property (nonatomic, assign) XSATool tool;
@property (nonatomic, assign) NSPoint startPt;
@property (nonatomic, assign) NSPoint endPt;
@property (nonatomic, strong) NSMutableArray<NSValue *> *points;
@property (nonatomic, strong) NSColor *color;
@property (nonatomic, assign) CGFloat lineWidth;
@property (nonatomic, strong) NSString *text;
@property (nonatomic, assign) CGFloat fontSize;
@end
@implementation XSAnnotation
- (instancetype)init {
    self = [super init];
    _points = [NSMutableArray array];
    _lineWidth = 3;
    _fontSize = 22;
    return self;
}
@end

@interface XSAnnotatePanel : NSPanel
@end
@implementation XSAnnotatePanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end

/// 透明文字格：不画底、不画边，字段编辑器也去掉背景
@interface XSPlainTextFieldCell : NSTextFieldCell
@end
@implementation XSPlainTextFieldCell
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    [self drawInteriorWithFrame:cellFrame inView:controlView];
}
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    [self.attributedStringValue drawWithRect:cellFrame
                                     options:NSStringDrawingUsesLineFragmentOrigin];
}
- (NSText *)setUpFieldEditorAttributes:(NSText *)textObj {
    NSText *t = [super setUpFieldEditorAttributes:textObj];
    if ([t isKindOfClass:[NSTextView class]]) {
        NSTextView *tv = (NSTextView *)t;
        tv.drawsBackground = NO;
        tv.backgroundColor = NSColor.clearColor;
        tv.insertionPointColor = self.textColor;
    }
    return t;
}
@end

@interface XSPlainTextField : NSTextField
@end
@implementation XSPlainTextField
+ (void)initialize {
    if (self == [XSPlainTextField class]) {
        [self setCellClass:[XSPlainTextFieldCell class]];
    }
}
- (BOOL)becomeFirstResponder {
    BOOL ok = [super becomeFirstResponder];
    NSTextView *editor = (NSTextView *)self.currentEditor;
    if ([editor isKindOfClass:[NSTextView class]]) {
        editor.drawsBackground = NO;
        editor.backgroundColor = NSColor.clearColor;
        editor.insertionPointColor = self.textColor;
    }
    return ok;
}
@end

@interface XSAnnotateCanvas : NSView <NSTextFieldDelegate>
@property (nonatomic, strong) NSImage *baseImage;
@property (nonatomic, strong) NSMutableArray<XSAnnotation *> *annotations;
@property (nonatomic, assign) XSATool currentTool;
@property (nonatomic, strong) NSColor *currentColor;
@property (nonatomic, assign) CGFloat currentLineWidth;
@property (nonatomic, assign) CGFloat currentFontSize;
@property (nonatomic, strong, nullable) XSAnnotation *activeAnnotation;
@property (nonatomic, copy, nullable) void (^onEsc)(void);
- (NSImage *)renderedImage;
- (void)undo;
- (void)commitTextIfNeeded;
- (BOOL)isEditingText;
@end

@implementation XSAnnotateCanvas {
    XSPlainTextField *_textField;
}

- (BOOL)isFlipped { return NO; }
- (BOOL)acceptsFirstResponder { return YES; }

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    _annotations = [NSMutableArray array];
    _currentColor = NSColor.systemRedColor;
    _currentLineWidth = 5;
    _currentFontSize = 22;
    return self;
}

- (NSDictionary *)textAttrs:(CGFloat)fontSize color:(NSColor *)color {
    NSColor *fg = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: color ?: NSColor.systemRedColor;
    return @{
        NSFontAttributeName: [NSFont systemFontOfSize:fontSize weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: fg,
    };
}

- (void)drawText:(NSString *)text at:(NSPoint)topLeft fontSize:(CGFloat)fontSize color:(NSColor *)color {
    NSDictionary *attrs = [self textAttrs:fontSize color:color];
    NSSize sz = [text sizeWithAttributes:attrs];
    [text drawAtPoint:NSMakePoint(topLeft.x, topLeft.y - sz.height) withAttributes:attrs];
}

- (void)drawRect:(NSRect)dirty {
    [self.baseImage drawInRect:self.bounds fromRect:NSZeroRect
                     operation:NSCompositingOperationCopy fraction:1
               respectFlipped:YES hints:nil];
    for (XSAnnotation *ann in self.annotations) [self renderAnnotation:ann];
    if (self.activeAnnotation && self.activeAnnotation.tool != XSAToolText)
        [self renderAnnotation:self.activeAnnotation];
}

- (void)renderAnnotation:(XSAnnotation *)ann {
    if (!ann.color) return;
    [ann.color setStroke];
    [ann.color setFill];
    switch (ann.tool) {
        case XSAToolRect: {
            NSBezierPath *p = [NSBezierPath bezierPathWithRect:[self normRect:ann.startPt b:ann.endPt]];
            p.lineWidth = ann.lineWidth;
            [p stroke];
            break;
        }
        case XSAToolEllipse: {
            NSBezierPath *p = [NSBezierPath bezierPathWithOvalInRect:[self normRect:ann.startPt b:ann.endPt]];
            p.lineWidth = ann.lineWidth;
            [p stroke];
            break;
        }
        case XSAToolArrow:
            [self drawArrow:ann.startPt to:ann.endPt lw:ann.lineWidth color:ann.color];
            break;
        case XSAToolPen: {
            if (ann.points.count < 2) break;
            NSBezierPath *p = [NSBezierPath bezierPath];
            p.lineWidth = ann.lineWidth;
            p.lineCapStyle = NSLineCapStyleRound;
            p.lineJoinStyle = NSLineJoinStyleRound;
            [p moveToPoint:ann.points.firstObject.pointValue];
            for (NSUInteger i = 1; i < ann.points.count; i++)
                [p lineToPoint:ann.points[i].pointValue];
            [p stroke];
            break;
        }
        case XSAToolText:
            if (ann.text.length) [self drawText:ann.text at:ann.startPt fontSize:ann.fontSize color:ann.color];
            break;
        case XSAToolMosaic: {
            if (ann.points.count < 2) break;
            [self drawMosaic:[self enclosingRect:ann.points]];
            break;
        }
    }
}

- (void)drawArrow:(NSPoint)a to:(NSPoint)b lw:(CGFloat)lw color:(NSColor *)c {
    if (NSEqualPoints(a, b)) return;
    [c setStroke]; [c setFill];
    CGFloat angle = atan2(b.y - a.y, b.x - a.x);
    CGFloat headLen = MAX(16, lw * 6);
    CGFloat spread = M_PI / 11.0;
    NSPoint shaftEnd = NSMakePoint(b.x - headLen * 0.6 * cos(angle), b.y - headLen * 0.6 * sin(angle));
    NSBezierPath *line = [NSBezierPath bezierPath];
    line.lineWidth = lw; line.lineCapStyle = NSLineCapStyleButt;
    [line moveToPoint:a]; [line lineToPoint:shaftEnd]; [line stroke];
    NSBezierPath *head = [NSBezierPath bezierPath];
    [head moveToPoint:b];
    [head lineToPoint:NSMakePoint(b.x - headLen * cos(angle - spread), b.y - headLen * sin(angle - spread))];
    [head lineToPoint:NSMakePoint(b.x - headLen * cos(angle + spread), b.y - headLen * sin(angle + spread))];
    [head closePath]; [head fill];
}

- (void)drawMosaic:(NSRect)r {
    if (r.size.width < 2 || r.size.height < 2) return;
    NSRect proposed = NSMakeRect(0, 0, self.baseImage.size.width, self.baseImage.size.height);
    CGImageRef cg = [self.baseImage CGImageForProposedRect:&proposed context:nil hints:nil];
    if (!cg) return;
    CGFloat sx = CGImageGetWidth(cg) / MAX(1, self.bounds.size.width);
    CGFloat sy = CGImageGetHeight(cg) / MAX(1, self.bounds.size.height);
    CGRect src = CGRectMake(r.origin.x * sx, (self.bounds.size.height - NSMaxY(r)) * sy,
                            r.size.width * sx, r.size.height * sy);
    CGImageRef crop = CGImageCreateWithImageInRect(cg, src);
    if (!crop) return;
    CIImage *ci = [CIImage imageWithCGImage:crop]; CGImageRelease(crop);
    CIFilter *pix = [CIFilter filterWithName:@"CIPixellate"];
    [pix setValue:ci forKey:kCIInputImageKey];
    [pix setValue:@(MAX(8, MIN(r.size.width, r.size.height) * 0.12)) forKey:kCIInputScaleKey];
    static CIContext *ctx;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ctx = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@NO}]; });
    CGImageRef pixCG = [ctx createCGImage:pix.outputImage fromRect:pix.outputImage.extent];
    if (!pixCG) return;
    CGContextRef gc = NSGraphicsContext.currentContext.CGContext;
    CGContextSaveGState(gc);
    CGContextClipToRect(gc, CGRectMake(r.origin.x, r.origin.y, r.size.width, r.size.height));
    CGContextDrawImage(gc, CGRectMake(r.origin.x, r.origin.y, r.size.width, r.size.height), pixCG);
    CGContextRestoreGState(gc);
    CGImageRelease(pixCG);
}

- (NSRect)normRect:(NSPoint)a b:(NSPoint)b {
    return NSMakeRect(MIN(a.x,b.x), MIN(a.y,b.y), fabs(b.x-a.x), fabs(b.y-a.y));
}
- (NSRect)enclosingRect:(NSArray<NSValue *> *)pts {
    CGFloat mnx=CGFLOAT_MAX,mny=CGFLOAT_MAX,mxx=-CGFLOAT_MAX,mxy=-CGFLOAT_MAX;
    for (NSValue *v in pts) { NSPoint p=v.pointValue; mnx=MIN(mnx,p.x); mny=MIN(mny,p.y); mxx=MAX(mxx,p.x); mxy=MAX(mxy,p.y); }
    return NSMakeRect(mnx, mny, mxx-mnx, mxy-mny);
}

- (void)mouseDown:(NSEvent *)event {
    [self commitTextIfNeeded];
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (self.currentTool == XSAToolText) { [self beginTextAt:p]; return; }
    XSAnnotation *ann = [XSAnnotation new];
    ann.tool = self.currentTool;
    ann.color = self.currentColor;
    ann.lineWidth = self.currentLineWidth;
    ann.fontSize = self.currentFontSize;
    ann.startPt = p; ann.endPt = p;
    [ann.points addObject:[NSValue valueWithPoint:p]];
    self.activeAnnotation = ann;
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.activeAnnotation || self.activeAnnotation.tool == XSAToolText) return;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    self.activeAnnotation.endPt = p;
    if (self.activeAnnotation.tool == XSAToolPen || self.activeAnnotation.tool == XSAToolMosaic)
        [self.activeAnnotation.points addObject:[NSValue valueWithPoint:p]];
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    if (!self.activeAnnotation || self.activeAnnotation.tool == XSAToolText) return;
    [self.annotations addObject:self.activeAnnotation];
    self.activeAnnotation = nil;
    [self setNeedsDisplay:YES];
}

- (void)beginTextAt:(NSPoint)p {
    [self commitTextIfNeeded];
    CGFloat fontSize = self.currentFontSize;
    CGFloat h = fontSize + 10;
    CGFloat w = MIN(MAX(80, self.bounds.size.width - p.x - 8), 480);
    NSRect fr = NSMakeRect(p.x, p.y - h, w, h);
    if (fr.origin.y < 0) { fr.size.height += fr.origin.y; fr.origin.y = 0; }
    if (fr.origin.x < 0) fr.origin.x = 0;

    _textField = [[XSPlainTextField alloc] initWithFrame:fr];
    _textField.font = [NSFont systemFontOfSize:fontSize weight:NSFontWeightSemibold];
    _textField.textColor = self.currentColor;
    _textField.drawsBackground = NO;
    _textField.backgroundColor = NSColor.clearColor;
    _textField.bordered = NO;
    _textField.bezeled = NO;
    _textField.editable = YES;
    _textField.selectable = YES;
    _textField.focusRingType = NSFocusRingTypeNone;
    _textField.delegate = self;
    _textField.placeholderString = @"";
    [self addSubview:_textField];
    [self.window makeFirstResponder:_textField];

    XSAnnotation *ann = [XSAnnotation new];
    ann.tool = XSAToolText;
    ann.color = self.currentColor;
    ann.startPt = NSMakePoint(fr.origin.x, fr.origin.y + h); // 左上角
    ann.fontSize = fontSize;
    self.activeAnnotation = ann;
}

- (BOOL)isEditingText { return _textField != nil; }

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (commandSelector == @selector(insertNewline:)) {
        [self commitTextIfNeeded];
        return YES;
    }
    if (commandSelector == @selector(cancelOperation:)) {
        [_textField removeFromSuperview];
        _textField = nil;
        self.activeAnnotation = nil;
        [self.window makeFirstResponder:self];
        return YES;
    }
    return NO;
}

- (void)commitTextIfNeeded {
    if (!_textField) return;
    NSString *text = [_textField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSPoint topLeft = self.activeAnnotation.startPt;
    [_textField removeFromSuperview];
    _textField = nil;
    XSAnnotation *ann = self.activeAnnotation;
    self.activeAnnotation = nil;
    if (ann && ann.tool == XSAToolText && text.length > 0) {
        ann.text = text;
        ann.startPt = topLeft;
        [self.annotations addObject:ann];
    }
    [self.window makeFirstResponder:self];
    [self setNeedsDisplay:YES];
}

- (void)undo {
    [self commitTextIfNeeded];
    if (self.annotations.count > 0) {
        [self.annotations removeLastObject];
        [self setNeedsDisplay:YES];
    }
}

- (void)keyDown:(NSEvent *)event {
    if (_textField) return;
    if (event.keyCode == 53) { if (self.onEsc) self.onEsc(); return; }
    NSEventModifierFlags m = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if ((m & NSEventModifierFlagCommand) && event.keyCode == 6) { [self undo]; return; }
    [super keyDown:event];
}

- (NSImage *)renderedImage {
    [self commitTextIfNeeded];
    NSBitmapImageRep *rep = [self bitmapImageRepForCachingDisplayInRect:self.bounds];
    if (rep) {
        [self cacheDisplayInRect:self.bounds toBitmapImageRep:rep];
        NSImage *out = [[NSImage alloc] initWithSize:self.bounds.size];
        [out addRepresentation:rep];
        return out;
    }
    NSImage *out = [[NSImage alloc] initWithSize:self.bounds.size];
    [out lockFocus]; [self drawRect:self.bounds]; [out unlockFocus];
    return out;
}

@end

@interface XSAnnotationWindowController () <NSWindowDelegate>
@end

@implementation XSAnnotationWindowController {
    XSAnnotatePanel *_overlayPanel;
    XSAnnotateCanvas *_canvas;
    NSView *_toolbar;
    NSArray<NSButton *> *_toolButtons;
    NSArray<NSButton *> *_strokeButtons;
    NSColor *_currentColor;
    CGFloat _currentLineWidth;
    CGFloat _currentFontSize;
    XSATool _activeTool;
    NSScreen *_screen;
}

+ (instancetype)shared {
    static XSAnnotationWindowController *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [[XSAnnotationWindowController alloc] init]; });
    return c;
}

- (instancetype)init {
    self = [super initWithWindow:nil];
    _currentColor = NSColor.systemRedColor;
    _currentLineWidth = 5;
    _currentFontSize = 22;
    _activeTool = XSAToolArrow;
    return self;
}

- (void)showWithImage:(NSImage *)image {
    if (!image) return;
    [self dismiss];

    NSApp.activationPolicy = NSApplicationActivationPolicyRegular;
    _screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    NSRect sf = _screen.frame;

    _overlayPanel = [[XSAnnotatePanel alloc] initWithContentRect:sf
                                                       styleMask:NSWindowStyleMaskBorderless
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
    _overlayPanel.level = NSScreenSaverWindowLevel;
    _overlayPanel.opaque = NO;
    _overlayPanel.backgroundColor = NSColor.clearColor;
    _overlayPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    _overlayPanel.releasedWhenClosed = NO;
    _overlayPanel.delegate = self;
    self.window = _overlayPanel;

    NSView *root = _overlayPanel.contentView;
    root.wantsLayer = YES;

    NSSize imgSz = image.size;
    CGFloat tbH = 56;
    CGFloat gap = 16;
    CGFloat margin = 36;
    CGFloat maxW = sf.size.width - margin * 2;
    CGFloat maxH = sf.size.height - margin * 2 - tbH - gap;
    CGFloat scale = MIN(1.0, MIN(maxW / MAX(1, imgSz.width), maxH / MAX(1, imgSz.height)));
    CGFloat dispW = round(imgSz.width * scale);
    CGFloat dispH = round(imgSz.height * scale);
    CGFloat imgX = round((sf.size.width - dispW) / 2.0);
    CGFloat imgY = round((sf.size.height - dispH - tbH - gap) / 2.0) + tbH + gap;
    NSRect imageFrame = NSMakeRect(imgX, imgY, dispW, dispH);

    NSView *dim = [[NSView alloc] initWithFrame:root.bounds];
    dim.wantsLayer = YES;
    dim.layer.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.62].CGColor;
    [root addSubview:dim];

    _canvas = [[XSAnnotateCanvas alloc] initWithFrame:imageFrame];
    _canvas.baseImage = image;
    _canvas.currentTool = _activeTool;
    _canvas.currentColor = _currentColor;
    _canvas.currentLineWidth = _currentLineWidth;
    _canvas.currentFontSize = _currentFontSize;
    __weak typeof(self) ws = self;
    _canvas.onEsc = ^{ [ws dismiss]; };
    [root addSubview:_canvas];

    NSBezierPath *border = [NSBezierPath bezierPathWithRect:NSInsetRect(imageFrame, -1, -1)];
    CAShapeLayer *borderLayer = [CAShapeLayer layer];
    borderLayer.path = border.CGPath;
    borderLayer.fillColor = NSColor.clearColor.CGColor;
    borderLayer.strokeColor = [[NSColor whiteColor] colorWithAlphaComponent:0.45].CGColor;
    borderLayer.lineWidth = 1;
    [root.layer addSublayer:borderLayer];

    // 工具条：固定足够宽，右侧预留圆角内边距，避免打勾被裁
    CGFloat tbW = 520;
    CGFloat tbX = round((sf.size.width - tbW) / 2.0);
    CGFloat tbY = imgY - gap - tbH;
    if (tbY < 12) tbY = imgY + dispH + gap;
    _toolbar = [[NSView alloc] initWithFrame:NSMakeRect(tbX, tbY, tbW, tbH)];
    _toolbar.wantsLayer = YES;
    _toolbar.layer.cornerRadius = 14;
    _toolbar.layer.masksToBounds = YES;
    _toolbar.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.16 alpha:0.96].CGColor;
    [root addSubview:_toolbar];
    [self buildToolbarIn:_toolbar];

    [_overlayPanel makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [_overlayPanel makeFirstResponder:_canvas];
}

- (void)buildToolbarIn:(NSView *)pill {
    CGFloat btnSz = 32;
    CGFloat gap = 6;
    CGFloat H = pill.bounds.size.height;
    CGFloat midY = round((H - btnSz) / 2.0);
    CGFloat x = 16;

    NSArray *defs = @[
        @[@"箭头",   @"arrow.up.right",  @(XSAToolArrow)],
        @[@"矩形",   @"rectangle",        @(XSAToolRect)],
        @[@"椭圆",   @"circle",           @(XSAToolEllipse)],
        @[@"画笔",   @"pencil",           @(XSAToolPen)],
        @[@"文字",   @"__T__",            @(XSAToolText)],
        @[@"马赛克", @"square.grid.2x2",  @(XSAToolMosaic)],
    ];
    NSMutableArray *btns = [NSMutableArray array];
    for (NSArray *def in defs) {
        NSButton *btn;
        if ([def[1] isEqualToString:@"__T__"]) {
            btn = [self makeImageButton:[self letterIcon:@"T"] tooltip:def[0] tag:[def[2] integerValue] action:@selector(toolTapped:)];
        } else {
            btn = [self makeIconButton:def[1] tooltip:def[0] tag:[def[2] integerValue] action:@selector(toolTapped:)];
        }
        btn.frame = NSMakeRect(x, midY, btnSz, btnSz);
        [pill addSubview:btn];
        [btns addObject:btn];
        x += btnSz + gap;
    }
    _toolButtons = [btns copy];

    x += 4;
    [self addSep:pill x:x y:12 h:H - 24];
    x += 12;

    CGFloat dots[] = {5, 9, 14};
    CGFloat vals[] = {2, 5, 10};
    NSMutableArray *sbtns = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        NSButton *sb = [self makeImageButton:[self dotIcon:dots[i]] tooltip:[NSString stringWithFormat:@"粗细 %.0f", vals[i]] tag:(NSInteger)vals[i] action:@selector(strokePresetTapped:)];
        sb.frame = NSMakeRect(x, midY, btnSz, btnSz);
        [pill addSubview:sb];
        [sbtns addObject:sb];
        x += btnSz + gap;
    }
    _strokeButtons = [sbtns copy];
    [self highlightStroke:_currentLineWidth];

    x += 4;
    [self addSep:pill x:x y:12 h:H - 24];
    x += 12;

    NSButton *undoBtn = [self makeIconButton:@"arrow.uturn.backward" tooltip:@"撤销 ⌘Z" tag:0 action:@selector(undoTapped:)];
    undoBtn.frame = NSMakeRect(x, midY, btnSz, btnSz);
    [pill addSubview:undoBtn];
    x += btnSz + 10;

    [self addSep:pill x:x y:12 h:H - 24];
    x += 12;

    NSButton *saveBtn = [self makeIconButton:@"square.and.arrow.down" tooltip:@"保存到本地" tag:0 action:@selector(saveTapped:)];
    saveBtn.frame = NSMakeRect(x, midY, btnSz, btnSz);
    [pill addSubview:saveBtn];
    x += btnSz + gap;

    NSButton *okBtn = [self makeImageButton:[self checkIcon] tooltip:@"复制到剪贴板" tag:0 action:@selector(copyClipboardTapped:)];
    okBtn.frame = NSMakeRect(x, midY, btnSz, btnSz);
    [pill addSubview:okBtn];

    [self highlightTool:_activeTool];

    CGFloat used = NSMaxX(okBtn.frame) + 20; // 右侧留白，躲开 14pt 圆角裁切
    NSView *parent = pill.superview;
    NSRect f = pill.frame;
    f.size.width = used;
    if (parent) f.origin.x = round((parent.bounds.size.width - used) / 2.0);
    pill.frame = f;
}

- (NSImage *)letterIcon:(NSString *)letter {
    return [NSImage imageWithSize:NSMakeSize(32, 32) flipped:NO drawingHandler:^BOOL(NSRect r) {
        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont boldSystemFontOfSize:18],
            NSForegroundColorAttributeName: NSColor.whiteColor,
        };
        NSSize sz = [letter sizeWithAttributes:attrs];
        [letter drawAtPoint:NSMakePoint((r.size.width - sz.width) / 2.0,
                                        (r.size.height - sz.height) / 2.0) withAttributes:attrs];
        return YES;
    }];
}

- (NSImage *)dotIcon:(CGFloat)d {
    return [NSImage imageWithSize:NSMakeSize(32, 32) flipped:NO drawingHandler:^BOOL(NSRect r) {
        [NSColor.whiteColor setFill];
        NSRect dot = NSMakeRect((r.size.width - d) / 2.0, (r.size.height - d) / 2.0, d, d);
        [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
        return YES;
    }];
}

- (NSImage *)checkIcon {
    return [NSImage imageWithSize:NSMakeSize(32, 32) flipped:NO drawingHandler:^BOOL(NSRect r) {
        NSBezierPath *p = [NSBezierPath bezierPath];
        p.lineWidth = 2.8;
        p.lineCapStyle = NSLineCapStyleRound;
        p.lineJoinStyle = NSLineJoinStyleRound;
        [p moveToPoint:NSMakePoint(8, 16)];
        [p lineToPoint:NSMakePoint(14, 10)];
        [p lineToPoint:NSMakePoint(24, 22)];
        [[NSColor colorWithCalibratedRed:0.25 green:0.86 blue:0.42 alpha:1] setStroke];
        [p stroke];
        return YES;
    }];
}

- (NSButton *)makeIconButton:(NSString *)sym tooltip:(NSString *)tip tag:(NSInteger)tag action:(SEL)action {
    NSImage *img = [NSImage imageWithSystemSymbolName:sym accessibilityDescription:tip];
    return [self makeImageButton:img tooltip:tip tag:tag action:action];
}

- (NSButton *)makeImageButton:(NSImage *)img tooltip:(NSString *)tip tag:(NSInteger)tag action:(SEL)action {
    NSButton *btn = [NSButton buttonWithTitle:@"" target:self action:action];
    if (img) { btn.image = img; btn.imagePosition = NSImageOnly; }
    else btn.title = tip;
    btn.bezelStyle = NSBezelStyleRegularSquare;
    btn.bordered = NO;
    btn.contentTintColor = NSColor.whiteColor;
    btn.wantsLayer = YES;
    btn.layer.cornerRadius = 7;
    btn.toolTip = tip;
    btn.tag = tag;
    return btn;
}

- (void)addSep:(NSView *)parent x:(CGFloat)x y:(CGFloat)y h:(CGFloat)h {
    NSView *sep = [[NSView alloc] initWithFrame:NSMakeRect(x, y, 1, h)];
    sep.wantsLayer = YES;
    sep.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.42 alpha:1].CGColor;
    [parent addSubview:sep];
}

- (void)highlightTool:(XSATool)tool {
    for (NSButton *b in _toolButtons) {
        BOOL on = b.tag == (NSInteger)tool;
        b.layer.backgroundColor = on ? [NSColor.controlAccentColor colorWithAlphaComponent:0.65].CGColor : NSColor.clearColor.CGColor;
    }
}

- (void)highlightStroke:(CGFloat)lw {
    for (NSButton *b in _strokeButtons) {
        BOOL on = labs(b.tag - (NSInteger)llround(lw)) == 0;
        b.layer.backgroundColor = on ? [NSColor.controlAccentColor colorWithAlphaComponent:0.55].CGColor : NSColor.clearColor.CGColor;
    }
}

- (void)toolTapped:(NSButton *)sender {
    [_canvas commitTextIfNeeded];
    _activeTool = (XSATool)sender.tag;
    _canvas.currentTool = _activeTool;
    [self highlightTool:_activeTool];
    [_overlayPanel makeFirstResponder:_canvas];
}

- (void)strokePresetTapped:(NSButton *)sender {
    _currentLineWidth = (CGFloat)sender.tag;
    _canvas.currentLineWidth = _currentLineWidth;
    [self highlightStroke:_currentLineWidth];
    [_overlayPanel makeFirstResponder:_canvas];
}

- (void)undoTapped:(id)sender {
    [_canvas undo];
    [_overlayPanel makeFirstResponder:_canvas];
}

- (void)copyClipboardTapped:(id)sender {
    [_canvas commitTextIfNeeded];
    NSImage *img = [_canvas renderedImage];
    if (!img) return;
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb clearContents];
    [pb writeObjects:@[img]];
    [self dismiss];
    [self showCopiedHUD];
}

- (void)saveTapped:(id)sender {
    [_canvas commitTextIfNeeded];
    NSImage *img = [_canvas renderedImage];
    if (!img) return;
    [self closeOverlaysKeepingActive];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSSavePanel *panel = [NSSavePanel savePanel];
        panel.allowedContentTypes = @[UTTypePNG];
        panel.nameFieldStringValue = @"xShot-annotated.png";
        NSModalResponse r = [panel runModal];
        NSApp.activationPolicy = NSApplicationActivationPolicyAccessory;
        if (r != NSModalResponseOK) return;
        NSRect proposed = NSMakeRect(0, 0, img.size.width, img.size.height);
        CGImageRef cg = [img CGImageForProposedRect:&proposed context:nil hints:nil];
        if (!cg) return;
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cg];
        NSData *data = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [data writeToURL:panel.URL atomically:YES];
    });
}

- (void)showCopiedHUD {
    NSScreen *s = _screen ?: NSScreen.mainScreen;
    NSRect sf = s ? s.frame : NSMakeRect(0, 0, 1440, 900);
    NSPanel *hud = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 148, 46)
                                              styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                backing:NSBackingStoreBuffered defer:NO];
    hud.level = NSFloatingWindowLevel + 10;
    hud.opaque = NO;
    hud.backgroundColor = NSColor.clearColor;
    hud.releasedWhenClosed = NO;
    NSView *bg = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 148, 46)];
    bg.wantsLayer = YES;
    bg.layer.cornerRadius = 10;
    bg.layer.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.72].CGColor;
    NSTextField *lbl = [NSTextField labelWithString:@"已复制到剪贴板"];
    lbl.textColor = NSColor.whiteColor;
    lbl.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    lbl.frame = NSMakeRect(8, 13, 132, 20);
    [bg addSubview:lbl];
    [hud.contentView addSubview:bg];
    [hud setFrame:NSMakeRect(sf.origin.x + (sf.size.width - 148) / 2, sf.origin.y + 60, 148, 46) display:NO];
    [hud orderFront:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [hud close];
    });
}

- (void)dismiss {
    [self closeOverlaysKeepingActive];
    NSApp.activationPolicy = NSApplicationActivationPolicyAccessory;
}

- (void)closeOverlaysKeepingActive {
    XSAnnotatePanel *panel = _overlayPanel;
    _overlayPanel = nil;
    _toolbar = nil;
    _canvas = nil;
    self.window = nil;
    [panel close];
}

- (void)windowWillClose:(NSNotification *)n {
    if (_overlayPanel) [self dismiss];
}

@end
