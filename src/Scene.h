#import <UIKit/UIKit.h>
#import <Metal/Metal.h>

@protocol Scene<NSObject>

@required

- (void)prepare:(id<MTLDevice>)device inFlightBuffersCount:(NSUInteger)buffersCount;

- (void)updateFrame:(NSUInteger)frameIndex elapsedTime:(float)elapsedTime drawableSize:(CGSize)drawableSize;

- (void)renderFrame:(id<MTLDevice>)device commandEncoder:(id<MTLRenderCommandEncoder>)commandEncoder frameIndex:(NSUInteger)frameIndex;

- (NSString *) title;

@end
