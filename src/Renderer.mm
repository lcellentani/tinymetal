#import "Renderer.h"
#import "SceneLighting.h"

#include "imgui.h"
#include "imgui_impl_metal.h"

@interface Renderer ()

@end

@implementation Renderer {
    dispatch_semaphore_t _inFlightSemaphore;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    
    CFTimeInterval _startupTime;
    CFTimeInterval _lastTime;
    float _currentTime;
    
    uint32_t _frameIndex;
    CGSize _drawableSize;
    
    id<Scene> _sceneLighting;
}

@synthesize device = _device;
-(NSUInteger) inFlightBuffersCount {
    static const NSUInteger cMaxBuffersInFlight = 3;
    return cMaxBuffersInFlight;
}

-(nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view; {
    self = [super init];
    if(self) {
        view.contentScaleFactor = [[UIScreen mainScreen] scale];
        view.clearColor = MTLClearColorMake(0.85, 0.85, 0.85, 1);
        view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        view.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
        view.sampleCount = 1;
        view.preferredFramesPerSecond = 60;
        
        _device = view.device;
        _commandQueue = [_device newCommandQueue];
        
        IMGUI_CHECKVERSION();
        ImGui::CreateContext();
        (void)ImGui::GetIO();
        ImGui_ImplMetal_Init(_device);
        ImGui::StyleColorsDark();
        
        _inFlightSemaphore = dispatch_semaphore_create(self.inFlightBuffersCount);
        
        _frameIndex = 0;
        _startupTime = CACurrentMediaTime();
        _lastTime = CACurrentMediaTime();
        _currentTime = 0;
        
        _sceneLighting = [SceneLighting newScene];
        [_sceneLighting prepareUsingRenderer:self];
    }
    return self;
}

#pragma mark - MTKViewDelegate methods
    
- (void)drawInMTKView:(nonnull MTKView *)view {
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);
    
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"CommandBuffer";
    
    __block dispatch_semaphore_t block_sema = _inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        dispatch_semaphore_signal(block_sema);
    }];
    
    _lastTime = _currentTime;
    _currentTime = CACurrentMediaTime() - _startupTime;
    float elapsed = _currentTime - _lastTime;
    
    [_sceneLighting updateFrame:_frameIndex elapsedTime:elapsed drawableSize:_drawableSize];
    
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    if (renderPassDescriptor == nil) {
        [commandBuffer commit];
        return;
    }
    
    id<MTLRenderCommandEncoder> commandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    commandEncoder.label = @"CommandEncoder";
    
    [commandEncoder pushDebugGroup:@"Draw scene"];
    
    [_sceneLighting renderFrame:_device commandEncoder:commandEncoder frameIndex:_frameIndex];
    
    [commandEncoder popDebugGroup];
    
    [commandEncoder pushDebugGroup:@"Draw ImGui"];
    
    ImGuiIO &io = ImGui::GetIO();
    io.DeltaTime = 1 / float(view.preferredFramesPerSecond ?: 60);
    ImGui_ImplMetal_NewFrame(renderPassDescriptor);
    
    ImGui::SetNextWindowPos(ImVec2(5.0f, 5.0f), ImGuiSetCond_FirstUseEver);
    ImGui::Begin("Global Params", nullptr, ImVec2(_drawableSize.width * 0.5f, _drawableSize.height * 0.1f), -1.f, ImGuiWindowFlags_AlwaysAutoResize);
    ImGui::Text("Time: %f ms", elapsed);
    ImGui::End();
    
    if ([_sceneLighting respondsToSelector:@selector(renderDebugFrame:)]) {
        [_sceneLighting renderDebugFrame:_drawableSize];
    }
    
    ImGui::Render();
    ImDrawData *drawData = ImGui::GetDrawData();
    ImGui_ImplMetal_RenderDrawData(drawData, commandBuffer, commandEncoder);
    
    [commandEncoder popDebugGroup];
    
    [commandEncoder endEncoding];
    
    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
    
    ++_frameIndex;
}
    
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
    _drawableSize = size;
    _drawableSize.width *= view.contentScaleFactor;
    _drawableSize.height *= view.contentScaleFactor;
    
    _frameIndex = 0;
    
    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize.x = size.width;
    io.DisplaySize.y = size.height;
    CGFloat framebufferScale = view.window.screen.scale ?: UIScreen.mainScreen.scale;
    io.DisplayFramebufferScale = ImVec2(framebufferScale, framebufferScale);
}
    
@end
