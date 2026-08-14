#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface XSPreset : NSObject <NSCopying>
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) CGFloat padding;
@property (nonatomic, assign) CGFloat inset;
@property (nonatomic, assign) BOOL balance;
@property (nonatomic, assign) BOOL insetColorAuto;
@property (nonatomic, strong) NSColor *insetColor;
@property (nonatomic, assign) CGFloat borderRadius;
@property (nonatomic, assign) CGFloat shadow;
@property (nonatomic, assign) CGFloat backgroundBlur;
@property (nonatomic, copy) NSString *backgroundId;
@property (nonatomic, strong, nullable) NSColor *customColor;
@property (nonatomic, strong, nullable) NSImage *customImage;
@property (nonatomic, copy) NSString *ratioId;
@property (nonatomic, assign) BOOL redactEmails;
@property (nonatomic, assign) BOOL showWatermark;
@property (nonatomic, copy) NSString *watermarkText;

+ (instancetype)defaultPreset;
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
@end

NS_ASSUME_NONNULL_END
