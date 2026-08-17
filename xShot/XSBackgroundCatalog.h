#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface XSBackgroundItem : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@end

@interface XSBackgroundCatalog : NSObject
+ (NSArray<XSBackgroundItem *> *)items;
+ (void)preloadWallpaperForId:(NSString *)identifier;
+ (void)trimCache;
+ (void)drawBackground:(NSString *)identifier
                inRect:(CGRect)rect
                 color:(nullable NSColor *)customColor
                 image:(nullable NSImage *)customImage;
+ (NSImage *)thumbnailForId:(NSString *)identifier size:(NSSize)size;
@end

NS_ASSUME_NONNULL_END
