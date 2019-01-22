#import <TargetConditionals.h>

#if TARGET_OS_IPHONE

#import <UIKit/UIKit.h>

@interface GameViewController : UIViewController

@end

#else

#import <Cocoa/Cocoa.h>

@interface GameViewControllerMacOS : NSViewController

@end

#endif
