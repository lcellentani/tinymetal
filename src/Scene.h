#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import "Renderer.h"

@protocol Scene<NSObject>

@required

- (void)prepareUsingRenderer:(Renderer *)renderer;

- (void)updateFrame:(NSUInteger)frameIndex elapsedTime:(float)elapsedTime drawableSize:(CGSize)drawableSize;

- (void)renderFrame:(id<MTLDevice>)device commandEncoder:(id<MTLRenderCommandEncoder>)commandEncoder frameIndex:(NSUInteger)frameIndex;

- (NSString *) title;

@optional

- (void) renderDebugFrame:(CGSize)drawableSize;

@end
