#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, XSHotKeyAction) {
    XSHotKeyActionCapture = 1,
    XSHotKeyActionPin = 2,
    XSHotKeyActionColorPicker = 3,
    XSHotKeyActionPlainCapture = 4,
    XSHotKeyActionAnnotate = 5,
};

@protocol XSHotKeyManagerDelegate <NSObject>
- (void)hotKeyActionTriggered:(XSHotKeyAction)action;
@end

@interface XSHotKeyManager : NSObject
@property (nonatomic, weak) id<XSHotKeyManagerDelegate> delegate;

+ (instancetype)shared;
- (void)registerAll;
- (void)unregisterAll;

- (UInt32)keyCodeForAction:(XSHotKeyAction)action;
- (UInt32)modifiersForAction:(XSHotKeyAction)action;
- (NSString *)displayForAction:(XSHotKeyAction)action;
- (void)updateAction:(XSHotKeyAction)action keyCode:(UInt32)keyCode modifiers:(UInt32)modifiers;

+ (NSString *)displayForKeyCode:(UInt32)keyCode modifiers:(UInt32)modifiers;
+ (NSString *)titleForAction:(XSHotKeyAction)action;
@end

NS_ASSUME_NONNULL_END
