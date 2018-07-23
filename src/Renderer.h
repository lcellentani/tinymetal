#import <MetalKit/MetalKit.h>

@interface Renderer : NSObject <MTKViewDelegate>

@property (nonatomic, nullable) id <MTLDevice> device;
@property (nonatomic, readonly) NSUInteger inFlightBuffersCount;

-(nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view;
    
@end
