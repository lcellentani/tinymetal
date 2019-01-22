#import "Scene.h"

@interface SceneTexturing : NSObject<Scene>

+ (id<Scene>)newScene;

- (instancetype)init;

- (void)prepareUsingRenderer:(Renderer *)renderer;

- (void)updateFrame:(NSUInteger)frameIndex elapsedTime:(float)elapsedTime drawableSize:(CGSize)drawableSize;

- (void)renderFrame:(id<MTLDevice>)device commandEncoder:(id<MTLRenderCommandEncoder>)commandEncoder frameIndex:(NSUInteger)frameIndex;

- (NSString *) title;

@end
