#import "XSPreset.h"

@implementation XSPreset

+ (instancetype)defaultPreset {
    XSPreset *p = [XSPreset new];
    p.name = @"Default";
    p.padding = 64;
    p.inset = 0;
    p.balance = YES;
    p.insetColorAuto = YES;
    p.insetColor = NSColor.whiteColor;
    p.borderRadius = 18;
    p.shadow = 28;
    p.backgroundBlur = 0;
    p.backgroundId = @"wp1";
    p.customColor = [NSColor colorWithCalibratedRed:0.45 green:0.55 blue:0.95 alpha:1];
    p.ratioId = @"auto";
    p.redactEmails = NO;
    p.showWatermark = NO;
    p.watermarkText = @"Screenshot by xShot";
    return p;
}

- (id)copyWithZone:(NSZone *)zone {
    return [XSPreset fromDictionary:[self toDictionary]];
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *d = [@{
        @"name": self.name ?: @"Default",
        @"padding": @(self.padding),
        @"inset": @(self.inset),
        @"balance": @(self.balance),
        @"insetColorAuto": @(self.insetColorAuto),
        @"borderRadius": @(self.borderRadius),
        @"shadow": @(self.shadow),
        @"backgroundBlur": @(self.backgroundBlur),
        @"backgroundId": self.backgroundId ?: @"wp1",
        @"ratioId": self.ratioId ?: @"auto",
        @"redactEmails": @(self.redactEmails),
        @"showWatermark": @(self.showWatermark),
        @"watermarkText": self.watermarkText ?: @"Screenshot by xShot",
    } mutableCopy];
    NSColor *ic = [self.insetColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    d[@"insetColor"] = @[ @(ic.redComponent), @(ic.greenComponent), @(ic.blueComponent), @(ic.alphaComponent) ];
    if (self.customColor) {
        NSColor *cc = [self.customColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        d[@"customColor"] = @[ @(cc.redComponent), @(cc.greenComponent), @(cc.blueComponent), @(cc.alphaComponent) ];
    }
    if (self.customImage) {
        NSData *tiff = [self.customImage TIFFRepresentation];
        if (tiff) d[@"customImage"] = [tiff base64EncodedStringWithOptions:0];
    }
    return d;
}

+ (NSColor *)colorFromArray:(NSArray *)arr fallback:(NSColor *)fallback {
    if (![arr isKindOfClass:NSArray.class] || arr.count < 3) return fallback;
    return [NSColor colorWithCalibratedRed:[arr[0] doubleValue]
                                     green:[arr[1] doubleValue]
                                      blue:[arr[2] doubleValue]
                                     alpha:arr.count > 3 ? [arr[3] doubleValue] : 1];
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    XSPreset *p = [self defaultPreset];
    if (![dict isKindOfClass:NSDictionary.class]) return p;
    if (dict[@"name"]) p.name = dict[@"name"];
    if (dict[@"padding"]) p.padding = [dict[@"padding"] doubleValue];
    if (dict[@"inset"]) p.inset = [dict[@"inset"] doubleValue];
    if (dict[@"balance"]) p.balance = [dict[@"balance"] boolValue];
    if (dict[@"insetColorAuto"]) p.insetColorAuto = [dict[@"insetColorAuto"] boolValue];
    if (dict[@"borderRadius"]) p.borderRadius = [dict[@"borderRadius"] doubleValue];
    if (dict[@"shadow"]) p.shadow = [dict[@"shadow"] doubleValue];
    if (dict[@"backgroundBlur"]) p.backgroundBlur = MAX(0, [dict[@"backgroundBlur"] doubleValue]);
    if (dict[@"backgroundId"]) {
        NSString *bg = dict[@"backgroundId"];
        if ([bg hasPrefix:@"wp"] || [bg isEqualToString:@"none"] || [bg isEqualToString:@"custom"]) {
            p.backgroundId = bg;
        } else {
            p.backgroundId = @"wp1";
        }
    }
    if (dict[@"ratioId"]) p.ratioId = dict[@"ratioId"];
    if (dict[@"redactEmails"]) p.redactEmails = [dict[@"redactEmails"] boolValue];
    if (dict[@"showWatermark"]) p.showWatermark = [dict[@"showWatermark"] boolValue];
    if (dict[@"watermarkText"]) p.watermarkText = dict[@"watermarkText"];
    if (dict[@"insetColor"]) p.insetColor = [self colorFromArray:dict[@"insetColor"] fallback:NSColor.whiteColor];
    if (dict[@"customColor"]) p.customColor = [self colorFromArray:dict[@"customColor"] fallback:p.customColor];
    if ([dict[@"customImage"] isKindOfClass:NSString.class]) {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:dict[@"customImage"] options:0];
        if (data) p.customImage = [[NSImage alloc] initWithData:data];
    }
    return p;
}

@end
