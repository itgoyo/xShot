#import "XSLaunchAtLoginManager.h"
#import <ServiceManagement/ServiceManagement.h>

@implementation XSLaunchAtLoginManager

+ (instancetype)shared {
    static XSLaunchAtLoginManager *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [XSLaunchAtLoginManager new]; });
    return m;
}

- (BOOL)isEnabled {
    if (@available(macOS 13.0, *)) {
        return [SMAppService mainAppService].status == SMAppServiceStatusEnabled;
    }
    return NO;
}

- (BOOL)setEnabled:(BOOL)enabled error:(NSError **)error {
    if (@available(macOS 13.0, *)) {
        if (enabled) return [[SMAppService mainAppService] registerAndReturnError:error];
        return [[SMAppService mainAppService] unregisterAndReturnError:error];
    }
    if (error) {
        *error = [NSError errorWithDomain:@"xShot" code:1 userInfo:@{NSLocalizedDescriptionKey: @"需要 macOS 13 或更高版本"}];
    }
    return NO;
}

@end
