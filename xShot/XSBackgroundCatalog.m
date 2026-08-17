#import "XSBackgroundCatalog.h"
#import <ImageIO/ImageIO.h>

@implementation XSBackgroundItem
@end

@implementation XSBackgroundCatalog

+ (NSString *)wallpapersDirectory {
    NSString *bundled = [[NSBundle mainBundle] resourcePath];
    NSString *inBundle = [bundled stringByAppendingPathComponent:@"Wallpapers"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:inBundle]) return inBundle;
    NSString *dev = [[[NSBundle mainBundle] bundlePath]
                     stringByDeletingLastPathComponent];
    dev = [[dev stringByDeletingLastPathComponent]
           stringByDeletingLastPathComponent];
    NSString *src = [dev stringByAppendingPathComponent:@"xShot/Resources/Wallpapers"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:src]) return src;
    return inBundle;
}

+ (void)preloadWallpaperForId:(NSString *)identifier {
    (void)[self wallpaperImageForId:identifier maxPixelSize:0];
}

+ (void)trimCache {
    [[self imageCache] removeAllObjects];
}

+ (NSArray<XSBackgroundItem *> *)items {
    static NSArray *items;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *arr = [NSMutableArray array];
        for (NSInteger i = 1; i <= 18; i++) {
            XSBackgroundItem *it = [XSBackgroundItem new];
            it.identifier = [NSString stringWithFormat:@"wp%ld", (long)i];
            it.title = [NSString stringWithFormat:@"%ld", (long)i];
            [arr addObject:it];
        }
        XSBackgroundItem *none = [XSBackgroundItem new];
        none.identifier = @"none";
        none.title = @"None";
        [arr addObject:none];
        XSBackgroundItem *custom = [XSBackgroundItem new];
        custom.identifier = @"custom";
        custom.title = @"Custom";
        [arr addObject:custom];
        items = arr;
    });
    return items;
}

+ (NSCache *)imageCache {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSCache new];
        cache.countLimit = 2;
        cache.totalCostLimit = 48 * 1024 * 1024;
    });
    return cache;
}

+ (NSString *)fileNameForId:(NSString *)identifier {
    if (![identifier hasPrefix:@"wp"]) return nil;
    NSString *num = [identifier substringFromIndex:2];
    return [NSString stringWithFormat:@"wallpaper%@.jpg", num];
}

+ (NSString *)pathForWallpaperId:(NSString *)identifier {
    NSString *file = [self fileNameForId:identifier];
    if (!file) return nil;
    NSString *path = [[self wallpapersDirectory] stringByAppendingPathComponent:file];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return path;
    NSString *name = [file stringByDeletingPathExtension];
    return [[NSBundle mainBundle] pathForResource:name ofType:@"jpg" inDirectory:@"Wallpapers"];
}

+ (NSUInteger)costForImage:(NSImage *)image {
    NSRect proposed = NSMakeRect(0, 0, image.size.width, image.size.height);
    CGImageRef cg = [image CGImageForProposedRect:&proposed context:nil hints:nil];
    if (!cg) return 1024;
    return (NSUInteger)CGImageGetWidth(cg) * (NSUInteger)CGImageGetHeight(cg) * 4;
}

+ (NSImage *)downscaledImage:(NSImage *)image maxPixelSize:(CGFloat)maxPixelSize {
    if (!image || maxPixelSize < 1) return image;
    NSRect proposed = NSMakeRect(0, 0, image.size.width, image.size.height);
    CGImageRef cg = [image CGImageForProposedRect:&proposed context:nil hints:nil];
    if (!cg) return image;
    CGFloat w = CGImageGetWidth(cg);
    CGFloat h = CGImageGetHeight(cg);
    if (MAX(w, h) <= maxPixelSize) return image;

    CGFloat scale = maxPixelSize / MAX(w, h);
    NSSize target = NSMakeSize(round(w * scale), round(h * scale));
    NSImage *small = [[NSImage alloc] initWithSize:target];
    [small lockFocus];
    [image drawInRect:NSMakeRect(0, 0, target.width, target.height)
             fromRect:NSZeroRect
            operation:NSCompositingOperationCopy
             fraction:1
       respectFlipped:YES
                hints:@{NSImageHintInterpolation: @(NSImageInterpolationMedium)}];
    [small unlockFocus];
    return small;
}

+ (NSImage *)jpegThumbnailForWallpaperId:(NSString *)identifier maxPixelSize:(CGFloat)maxPixelSize {
    NSString *path = [self pathForWallpaperId:identifier];
    if (!path) return nil;
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!src) return nil;
    NSDictionary *opts = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @(maxPixelSize),
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
    };
    CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
    CFRelease(src);
    if (!cg) return nil;
    NSImage *img = [[NSImage alloc] initWithCGImage:cg size:NSZeroSize];
    CGImageRelease(cg);
    return img;
}

+ (NSImage *)wallpaperImageForId:(NSString *)identifier maxPixelSize:(CGFloat)maxPixelSize {
    if (identifier.length == 0) return nil;
    NSString *cacheKey = maxPixelSize > 0
        ? [NSString stringWithFormat:@"%@-%0.f", identifier, maxPixelSize]
        : identifier;
    NSImage *cached = [[self imageCache] objectForKey:cacheKey];
    if (cached) return cached;

    NSString *path = [self pathForWallpaperId:identifier];
    if (!path) return nil;

    CGFloat target = maxPixelSize > 0 ? maxPixelSize : 1400;
    NSImage *img = [self jpegThumbnailForWallpaperId:identifier maxPixelSize:target];
    if (!img) {
        img = [[NSImage alloc] initWithContentsOfFile:path];
        img = [self downscaledImage:img maxPixelSize:target];
    }
    if (!img) return nil;
    [[self imageCache] setObject:img forKey:cacheKey cost:[self costForImage:img]];
    return img;
}

+ (NSImage *)wallpaperImageForId:(NSString *)identifier {
    return [self wallpaperImageForId:identifier maxPixelSize:1400];
}

+ (void)drawImageAspectFill:(NSImage *)image inRect:(CGRect)rect {
    if (!image) return;
    NSSize sz = image.size;
    if (sz.width < 1 || sz.height < 1) return;
    CGFloat scale = MAX(rect.size.width / sz.width, rect.size.height / sz.height);
    CGFloat w = sz.width * scale;
    CGFloat h = sz.height * scale;
    CGRect draw = CGRectMake(rect.origin.x + (rect.size.width - w) / 2.0,
                             rect.origin.y + (rect.size.height - h) / 2.0,
                             w, h);
    CGContextRef ctx = NSGraphicsContext.currentContext.CGContext;
    CGContextSaveGState(ctx);
    CGContextClipToRect(ctx, rect);
    [image drawInRect:draw fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1
       respectFlipped:YES hints:@{NSImageHintInterpolation: @(NSImageInterpolationMedium)}];
    CGContextRestoreGState(ctx);
}

+ (void)drawBackground:(NSString *)identifier
                inRect:(CGRect)rect
                 color:(NSColor *)customColor
                 image:(NSImage *)customImage {
    if ([identifier isEqualToString:@"none"]) return;
    if ([identifier isEqualToString:@"custom"]) {
        if (customImage) {
            [self drawImageAspectFill:customImage inRect:rect];
            return;
        }
        if (customColor) {
            [customColor setFill];
            NSRectFill(rect);
            return;
        }
    }
    CGFloat maxEdge = MAX(rect.size.width, rect.size.height);
    maxEdge = MIN(1400, MAX(320, maxEdge * 1.25));
    NSImage *wall = [self wallpaperImageForId:identifier maxPixelSize:maxEdge];
    if (wall) {
        [self drawImageAspectFill:wall inRect:rect];
        return;
    }
    NSColor *a = [NSColor colorWithCalibratedRed:0.35 green:0.55 blue:0.95 alpha:1];
    NSColor *b = [NSColor colorWithCalibratedRed:0.75 green:0.45 blue:0.90 alpha:1];
    NSGradient *g = [[NSGradient alloc] initWithStartingColor:a endingColor:b];
    [g drawInRect:rect angle:135];
}

+ (NSImage *)thumbnailForId:(NSString *)identifier size:(NSSize)size {
    NSImage *img = [[NSImage alloc] initWithSize:size];
    [img lockFocus];
    if ([identifier isEqualToString:@"none"]) {
        [[NSColor colorWithWhite:0.92 alpha:1] setFill];
        NSRectFill(NSMakeRect(0, 0, size.width, size.height));
        [[NSColor colorWithWhite:0.78 alpha:1] setFill];
        CGFloat cell = 6;
        for (int y = 0; y < size.height / cell + 1; y++)
            for (int x = 0; x < size.width / cell + 1; x++)
                if ((x + y) % 2 == 0)
                    NSRectFill(NSMakeRect(x * cell, y * cell, cell, cell));
    } else if ([identifier isEqualToString:@"custom"]) {
        [[NSColor colorWithWhite:0.88 alpha:1] setFill];
        NSRectFill(NSMakeRect(0, 0, size.width, size.height));
        NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
        ps.alignment = NSTextAlignmentCenter;
        [@"+" drawInRect:NSMakeRect(0, size.height / 2 - 8, size.width, 16) withAttributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: [NSColor colorWithWhite:0.35 alpha:1],
            NSParagraphStyleAttributeName: ps
        }];
    } else {
        NSImage *thumb = [self jpegThumbnailForWallpaperId:identifier maxPixelSize:MAX(size.width, size.height) * 2.0];
        if (thumb) {
            [self drawImageAspectFill:thumb inRect:NSMakeRect(0, 0, size.width, size.height)];
        } else {
            [self drawBackground:identifier inRect:NSMakeRect(0, 0, size.width, size.height) color:nil image:nil];
        }
    }
    [img unlockFocus];
    return img;
}

@end
