#import "XSBackgroundCatalog.h"

@implementation XSBackgroundItem
@end

@implementation XSBackgroundCatalog

+ (NSString *)wallpapersDirectory {
    NSString *bundled = [[NSBundle mainBundle] resourcePath];
    NSString *inBundle = [bundled stringByAppendingPathComponent:@"Wallpapers"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:inBundle]) return inBundle;
    // Dev fallback: source tree next to executable / relative to CWD
    NSString *dev = [[[NSBundle mainBundle] bundlePath]
                     stringByDeletingLastPathComponent]; // Contents
    dev = [[dev stringByDeletingLastPathComponent] // .app
           stringByDeletingLastPathComponent]; // dist
    NSString *src = [dev stringByAppendingPathComponent:@"xShot/Resources/Wallpapers"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:src]) return src;
    return inBundle;
}

+ (void)preloadWallpaperForId:(NSString *)identifier {
    (void)[self wallpaperImageForId:identifier];
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
        cache.countLimit = 24;
    });
    return cache;
}

+ (NSString *)fileNameForId:(NSString *)identifier {
    if (![identifier hasPrefix:@"wp"]) return nil;
    NSString *num = [identifier substringFromIndex:2];
    return [NSString stringWithFormat:@"wallpaper%@.jpg", num];
}

+ (NSImage *)wallpaperImageForId:(NSString *)identifier {
    if (identifier.length == 0) return nil;
    NSImage *cached = [[self imageCache] objectForKey:identifier];
    if (cached) return cached;

    NSString *file = [self fileNameForId:identifier];
    if (!file) return nil;
    NSString *path = [[self wallpapersDirectory] stringByAppendingPathComponent:file];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        // also try NSBundle resource lookup
        NSString *name = [file stringByDeletingPathExtension];
        path = [[NSBundle mainBundle] pathForResource:name ofType:@"jpg" inDirectory:@"Wallpapers"];
    }
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;

    NSImage *img = [[NSImage alloc] initWithContentsOfFile:path];
    if (!img) return nil;

    NSSize sz = img.size;
    CGFloat maxEdge = 2200;
    if (MAX(sz.width, sz.height) > maxEdge) {
        CGFloat scale = maxEdge / MAX(sz.width, sz.height);
        NSSize target = NSMakeSize(sz.width * scale, sz.height * scale);
        NSImage *small = [[NSImage alloc] initWithSize:target];
        [small lockFocus];
        [img drawInRect:NSMakeRect(0, 0, target.width, target.height)
               fromRect:NSZeroRect
              operation:NSCompositingOperationCopy
               fraction:1
         respectFlipped:YES
                  hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
        [small unlockFocus];
        img = small;
    }
    [[self imageCache] setObject:img forKey:identifier];
    return img;
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
       respectFlipped:YES hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
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
    NSImage *wall = [self wallpaperImageForId:identifier];
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
        [self drawBackground:identifier inRect:NSMakeRect(0, 0, size.width, size.height) color:nil image:nil];
    }
    [img unlockFocus];
    return img;
}

@end
