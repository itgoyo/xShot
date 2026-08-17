#import "XSImageRenderer.h"
#import "XSPreset.h"
#import "XSBackgroundCatalog.h"
#import <CoreImage/CoreImage.h>

@implementation XSImageRenderer

+ (CGFloat)aspectForRatioId:(NSString *)ratioId {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"auto": @0,
            @"4:3": @(4.0 / 3.0),
            @"3:2": @(3.0 / 2.0),
            @"16:9": @(16.0 / 9.0),
            @"1:1": @1,
            @"twitter": @(1200.0 / 675.0),
            @"facebook": @(1200.0 / 630.0),
            @"instagram": @1,
            @"linkedin": @(1200.0 / 627.0),
            @"youtube": @(16.0 / 9.0),
            @"pinterest": @(1000.0 / 1500.0),
            @"reddit": @(1200.0 / 628.0),
            @"snapchat": @(9.0 / 16.0),
        };
    });
    return [map[ratioId] doubleValue];
}

+ (void)warmup {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSImage *dot = [[NSImage alloc] initWithSize:NSMakeSize(4, 4)];
            [self blurredImage:dot radius:0];
        });
    });
}

+ (NSColor *)sampleColorFromCGImage:(CGImageRef)cg x:(NSInteger)x y:(NSInteger)y {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    unsigned char px[4] = {0};
    CGContextRef ctx = CGBitmapContextCreate(px, 1, 1, 8, 4, cs, kCGImageAlphaPremultipliedLast);
    if (ctx) {
        CGContextDrawImage(ctx, CGRectMake(-x, -y, CGImageGetWidth(cg), CGImageGetHeight(cg)), cg);
        CGContextRelease(ctx);
    }
    CGColorSpaceRelease(cs);
    return [NSColor colorWithCalibratedRed:px[0] / 255.0 green:px[1] / 255.0 blue:px[2] / 255.0 alpha:1];
}

+ (NSColor *)detectBackgroundColor:(NSImage *)image {
    NSRect proposed = NSMakeRect(0, 0, image.size.width, image.size.height);
    CGImageRef cg = [image CGImageForProposedRect:&proposed context:nil hints:nil];
    if (!cg) return NSColor.whiteColor;
    NSInteger w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    if (w < 4 || h < 4) return NSColor.whiteColor;
    NSPoint samples[] = {
        {2, 2}, {w - 3, 2}, {2, h - 3}, {w - 3, h - 3},
        {w / 2.0, 2}, {2, h / 2.0}
    };
    CGFloat r = 0, g = 0, b = 0;
    int n = 6;
    for (int i = 0; i < n; i++) {
        NSColor *c = [self sampleColorFromCGImage:cg x:(NSInteger)samples[i].x y:(NSInteger)samples[i].y];
        c = [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        r += c.redComponent; g += c.greenComponent; b += c.blueComponent;
    }
    return [NSColor colorWithCalibratedRed:r / n green:g / n blue:b / n alpha:1];
}

+ (NSImage *)blurredImage:(NSImage *)image radius:(CGFloat)radius {
    if (!image || radius < 0.5) return image;
    NSRect proposed = NSMakeRect(0, 0, image.size.width, image.size.height);
    CGImageRef cg = [image CGImageForProposedRect:&proposed context:nil hints:nil];
    if (!cg) return image;

    CGFloat pixelW = CGImageGetWidth(cg);
    CGFloat pixelH = CGImageGetHeight(cg);
    CGFloat workScale = 1.0;
    CGFloat maxEdge = 1200.0;
    if (MAX(pixelW, pixelH) > maxEdge) {
        workScale = maxEdge / MAX(pixelW, pixelH);
    }

    CIImage *input = [[CIImage alloc] initWithCGImage:cg];
    if (workScale < 0.999) {
        CIFilter *scale = [CIFilter filterWithName:@"CILanczosScaleTransform"];
        [scale setValue:input forKey:kCIInputImageKey];
        [scale setValue:@(workScale) forKey:kCIInputScaleKey];
        [scale setValue:@1.0 forKey:kCIInputAspectRatioKey];
        input = scale.outputImage;
    }

    CGFloat scale = (CGImageGetWidth(cg) / MAX(1.0, image.size.width)) * workScale;
    CIFilter *clamp = [CIFilter filterWithName:@"CIAffineClamp"];
    [clamp setDefaults];
    [clamp setValue:input forKey:kCIInputImageKey];
    [clamp setValue:[NSAffineTransform transform] forKey:kCIInputTransformKey];

    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blur setValue:clamp.outputImage forKey:kCIInputImageKey];
    [blur setValue:@(radius * scale) forKey:kCIInputRadiusKey];

    CIImage *output = [blur.outputImage imageByCroppingToRect:input.extent];
    static CIContext *ciCtx;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ciCtx = [CIContext contextWithOptions:@{
            kCIContextUseSoftwareRenderer: @NO,
            kCIContextCacheIntermediates: @NO,
        }];
    });
    CGImageRef outCG = [ciCtx createCGImage:output fromRect:input.extent];
    if (!outCG) return image;
    NSImage *out = [[NSImage alloc] initWithCGImage:outCG size:image.size];
    CGImageRelease(outCG);
    return out;
}

+ (NSImage *)roundedImage:(NSImage *)image radius:(CGFloat)radius {
    NSSize size = image.size;
    if (size.width < 1 || size.height < 1) return image;
    CGFloat r = MIN(radius, MIN(size.width, size.height) / 2.0);
    NSImage *out = [[NSImage alloc] initWithSize:size];
    [out lockFocus];
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, size.width, size.height) xRadius:r yRadius:r];
    [path addClip];
    [image drawInRect:NSMakeRect(0, 0, size.width, size.height) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
    [out unlockFocus];
    return out;
}

+ (NSImage *)renderSource:(NSImage *)source preset:(XSPreset *)preset {
    if (!source || source.size.width < 1) return source;
    NSSize src = source.size;
    CGFloat pad = MAX(0, preset.padding);
    CGFloat inset = MAX(0, preset.inset);
    CGFloat radius = MAX(0, preset.borderRadius);
    CGFloat shadow = MAX(0, preset.shadow);
    CGFloat shadowBlur = shadow * 0.85;
    CGFloat shadowPad = shadowBlur * 1.35;

    NSColor *cardColor = preset.insetColorAuto ? [self detectBackgroundColor:source] : (preset.insetColor ?: NSColor.whiteColor);
    NSImage *shot = [self roundedImage:source radius:MAX(0, radius - (inset > 0 ? 4 : 0))];

    CGFloat cardW = src.width + inset * 2;
    CGFloat cardH = src.height + inset * 2;
    CGFloat cardRadius = radius;

    CGFloat needW = cardW + pad * 2;
    CGFloat needH = cardH + pad * 2;
    CGFloat aspect = [self aspectForRatioId:preset.ratioId];
    CGFloat canvasW = needW, canvasH = needH;
    if (aspect > 0.01) {
        if (needW / needH < aspect) {
            canvasW = needH * aspect;
            canvasH = needH;
        } else {
            canvasW = needW;
            canvasH = needW / aspect;
        }
    }

    BOOL transparent = [preset.backgroundId isEqualToString:@"none"];
    canvasW += shadowPad * 2;
    canvasH += shadowPad * 2;

    NSRect canvasRect = NSMakeRect(0, 0, canvasW, canvasH);
    NSImage *bgLayer = nil;
    if (!transparent) {
        bgLayer = [[NSImage alloc] initWithSize:NSMakeSize(canvasW, canvasH)];
        [bgLayer lockFocus];
        [XSBackgroundCatalog drawBackground:preset.backgroundId inRect:canvasRect color:preset.customColor image:preset.customImage];
        [bgLayer unlockFocus];
        CGFloat bgBlur = MAX(0, preset.backgroundBlur);
        if (bgBlur >= 0.5) bgLayer = [self blurredImage:bgLayer radius:bgBlur];
    }

    NSImage *canvas = [[NSImage alloc] initWithSize:NSMakeSize(canvasW, canvasH)];
    [canvas lockFocus];
    if (bgLayer) {
        [bgLayer drawInRect:canvasRect fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1];
        bgLayer = nil;
    }

    NSRect cardRect = NSMakeRect((canvasW - cardW) / 2.0, (canvasH - cardH) / 2.0, cardW, cardH);
    if (preset.balance) {
        cardRect.origin.x = (canvasW - cardW) / 2.0;
        cardRect.origin.y = (canvasH - cardH) / 2.0;
    }

    NSGraphicsContext *gc = NSGraphicsContext.currentContext;
    CGContextRef ctx = gc.CGContext;
    CGContextSaveGState(ctx);
    if (shadow > 0.5) {
        NSShadow *sh = [NSShadow new];
        sh.shadowBlurRadius = shadowBlur;
        sh.shadowOffset = NSMakeSize(0, -shadow * 0.18);
        sh.shadowColor = [[NSColor blackColor] colorWithAlphaComponent:MIN(0.55, 0.18 + shadow / 180.0)];
        [sh set];
    }

    NSBezierPath *cardPath = [NSBezierPath bezierPathWithRoundedRect:cardRect xRadius:cardRadius yRadius:cardRadius];
    [cardColor setFill];
    [cardPath fill];
    CGContextRestoreGState(ctx);

    NSRect shotRect = NSInsetRect(cardRect, inset, inset);
    [shot drawInRect:shotRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];

    if (preset.showWatermark && preset.watermarkText.length) {
        NSShadow *ts = [NSShadow new];
        ts.shadowBlurRadius = 4;
        ts.shadowOffset = NSMakeSize(0, -1);
        ts.shadowColor = [[NSColor blackColor] colorWithAlphaComponent:0.35];
        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:MAX(11, canvasW / 70.0) weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: [[NSColor whiteColor] colorWithAlphaComponent:0.92],
            NSShadowAttributeName: ts
        };
        NSSize t = [preset.watermarkText sizeWithAttributes:attrs];
        NSPoint origin = NSMakePoint((canvasW - t.width) / 2.0, MAX(10, pad * 0.22));
        [preset.watermarkText drawAtPoint:origin withAttributes:attrs];
    }

    [canvas unlockFocus];
    return canvas;
}

@end
