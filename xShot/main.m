#import <Cocoa/Cocoa.h>
#import "XSAppDelegate.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        app.activationPolicy = NSApplicationActivationPolicyAccessory;
        XSAppDelegate *delegate = [XSAppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
