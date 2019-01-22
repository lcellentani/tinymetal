#import "GameViewController.h"

#import <MetalKit/MetalKit.h>

#import "Renderer.h"

#if TARGET_OS_IPHONE

#include "imgui.h"

@interface GameViewController ()

@end

@implementation GameViewController {
    MTKView* _view;
    Renderer* _renderer;
}

- (instancetype)initWithNibName:(NSString*)nibNameOrNil bundle:(NSBundle*)nibBundleOrNil {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
    }
    return self;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _view = (MTKView *)self.view;
    _view.device = MTLCreateSystemDefaultDevice();
    _view.backgroundColor = [UIColor blackColor];
    
    if (!_view.device) {
        NSLog(@"Metal is not supported on this device");
        self.view = [[UIView alloc] initWithFrame:self.view.frame];
        return;
    }
    
    _renderer = [[Renderer alloc] initWithMetalKitView:_view];
    [_renderer mtkView:_view drawableSizeWillChange:_view.bounds.size];
    _view.delegate = _renderer;
}

#pragma mark - Touches handling

- (void)updateIOWithTouchEvent:(UIEvent *)event {
    UITouch *anyTouch = event.allTouches.anyObject;
    CGPoint touchLocation = [anyTouch locationInView:self.view];
    ImGuiIO &io = ImGui::GetIO();
    io.MousePos = ImVec2(touchLocation.x, touchLocation.y);
    
    BOOL hasActiveTouch = NO;
    for (UITouch *touch in event.allTouches) {
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) {
            hasActiveTouch = YES;
            break;
        }
    }
    io.MouseDown[0] = hasActiveTouch;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self updateIOWithTouchEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self updateIOWithTouchEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self updateIOWithTouchEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self updateIOWithTouchEvent:event];
}

@end

#else

@interface GameViewControllerMacOS ()

@end

@implementation GameViewControllerMacOS {
    MTKView* _view;
    Renderer* _renderer;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _view = (MTKView *)self.view;
    _view.device = MTLCreateSystemDefaultDevice();
    //_view.backgroundColor = [UIColor blackColor];
    
    if (!_view.device) {
        NSLog(@"Metal is not supported on this device");
        self.view = [[NSView alloc] initWithFrame:self.view.frame];
        return;
    }
    
    _renderer = [[Renderer alloc] initWithMetalKitView:_view];
    [_renderer mtkView:_view drawableSizeWillChange:_view.bounds.size];
    _view.delegate = _renderer;
}


- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
}


@end

#endif
