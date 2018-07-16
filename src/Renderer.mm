#import "Renderer.h"
#import "GraphicsTypes.h"
#import "MathUtils.h"
#import "ObjMesh.h"
#import "ObjModel.h"
#import "ObjGroup.h"
#import "PositionNormalVertexFormat.h"

#include "imgui.h"
#include "imgui_impl_metal.h"

static const NSUInteger cMaxBuffersInFlight = 3;

@interface Renderer ()

@end

@implementation Renderer {
    dispatch_semaphore_t _inFlightSemaphore;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    
    struct PerFrameData {
        id<MTLBuffer> sharedData;
    } _perFrameData[cMaxBuffersInFlight];
    
    CFTimeInterval _startupTime;
    CFTimeInterval _lastTime;
    
    uint32_t _frameIndex;
    CGSize _drawableSize;
    
    id<MTLRenderPipelineState> _renderPipelineState;
    id<MTLDepthStencilState> _depthStencilState;
    
    ObjMesh* _mesh;
    
    id<MTLBuffer> _vertexBuffer;
    id<MTLBuffer> _indexBuffer;
    
    float _currentTime;
    float _rotationX;
    float _rotationY;
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
        
        [self makePipeline];
        [self makeResources];
        [self makeSharedData];
        
        _inFlightSemaphore = dispatch_semaphore_create(cMaxBuffersInFlight);
    }
    return self;
}

- (void)makePipeline {
    NSError *error = nil;
    
    id<MTLLibrary> library = [_device newDefaultLibrary];
    
    MTLDepthStencilDescriptor *depthStencilDescriptor = [MTLDepthStencilDescriptor new];
    depthStencilDescriptor.depthCompareFunction = MTLCompareFunctionLess;
    depthStencilDescriptor.depthWriteEnabled = YES;
    _depthStencilState = [_device newDepthStencilStateWithDescriptor:depthStencilDescriptor];
    
    MTLVertexDescriptor* vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];
    vertexDescriptor.attributes[0].format = MTLVertexFormatFloat4;
    vertexDescriptor.attributes[0].bufferIndex = 0;
    vertexDescriptor.attributes[0].offset = 0;
    vertexDescriptor.attributes[1].format = MTLVertexFormatFloat4;
    vertexDescriptor.attributes[1].bufferIndex = 0;
    vertexDescriptor.attributes[1].offset = sizeof(float) * 4;
    vertexDescriptor.layouts[0].stride = sizeof(float) * 8;
    vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    MTLRenderPipelineDescriptor *pipelineDescriptor = [MTLRenderPipelineDescriptor new];
    pipelineDescriptor.vertexFunction = [library newFunctionWithName:@"vertex_project"];
    pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"fragment_light"];
    pipelineDescriptor.vertexDescriptor = vertexDescriptor;
    pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    _renderPipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    NSAssert(_renderPipelineState, @"Error occurred when creating render pipeline state: %@", error);
}

- (void)makeResources {
    //NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"teapot" withExtension:@"obj"];
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"monkey" withExtension:@"obj"];
    ObjModel *model = [[ObjModel alloc] initWithContentsOfURL:modelURL generateNormals:YES];
    //ObjGroup *group = [model groupForName:@"teapot"];
    ObjGroup *group = [model groupAtIndex:0];
    
    PositionNormalVertexFormat* vertexFormat = [PositionNormalVertexFormat newVertexFormat:[group verticesCount]];
    _mesh = [[ObjMesh alloc] initWithGroup:group device:_device vertexFormat:vertexFormat];
}

- (void)makeSharedData {
    for (uint32_t i = 0; i < cMaxBuffersInFlight; ++i) {
        _perFrameData[i].sharedData = [_device newBufferWithLength:sizeof(SharedData) options:MTLResourceOptionCPUCacheModeDefault];
    }
    _startupTime = CACurrentMediaTime();
    _lastTime = CACurrentMediaTime();
    
    _frameIndex = 0;
    _currentTime = 0.0f;
    _rotationX = 0.0f;
    _rotationY = 0.0;
}

- (void)updateSharedData {
    _lastTime = _currentTime;
    _currentTime = CACurrentMediaTime() - _startupTime;
    float elapsed = _currentTime - _lastTime;
    
    _rotationX += elapsed * (M_PI / 2);
    _rotationY += elapsed * (M_PI / 3);
    float scaleFactor = 0.5f;
    const vector_float3 xAxis = { 1, 0, 0 };
    const vector_float3 yAxis = { 0, 1, 0 };
    const matrix_float4x4 xRot = matrix_float4x4_rotation(xAxis, _rotationX);
    const matrix_float4x4 yRot = matrix_float4x4_rotation(yAxis, _rotationY);
    const matrix_float4x4 scale = matrix_float4x4_uniform_scale(scaleFactor);
    const matrix_float4x4 modelMatrix = matrix_multiply(matrix_multiply(xRot, yRot), scale);
    
    const vector_float3 cameraTranslation = { 0, 0, -1.5 };
    const matrix_float4x4 viewMatrix = matrix_float4x4_translation(cameraTranslation);
    
    const float aspect = _drawableSize.width / _drawableSize.height;
    const float fov = (2.0f * M_PI) / 5.0f;
    const float near = 0.1f;
    const float far = 100.0f;
    const matrix_float4x4 projectionMatrix = matrix_float4x4_perspective(aspect, fov, near, far);
    
    SharedData data;
    data.u_frameIndex = _frameIndex;
    data.u_time = elapsed;
    data.u_modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix));
    data.u_modelViewMatrix = matrix_multiply(viewMatrix, modelMatrix);
    data.u_normalMatrix = matrix_float4x4_extract_linear(data.u_modelViewMatrix);
    
    id<MTLBuffer> sharedDataBuffer = _perFrameData[_frameIndex % cMaxBuffersInFlight].sharedData;
    memcpy([sharedDataBuffer contents], &data, sizeof(SharedData));
}
    
#pragma mark - MTKViewDelegate methods
    
- (void)drawInMTKView:(nonnull MTKView *)view {
    static bool show_demo_window = true;
    static bool show_another_window = true;
    static float clear_color[4] = { 0.28f, 0.36f, 0.5f, 1.0f };
    
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);
    
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"CommandBuffer";
    
    __block dispatch_semaphore_t block_sema = _inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        dispatch_semaphore_signal(block_sema);
    }];
    
    [self updateSharedData];
    
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    if (renderPassDescriptor == nil) {
        [commandBuffer commit];
        return;
    }
    
    id<MTLRenderCommandEncoder> commandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    commandEncoder.label = @"CommandEncoder";
    
    [commandEncoder pushDebugGroup:@"Draw scene"];
    
    [commandEncoder setRenderPipelineState:_renderPipelineState];
    [commandEncoder setDepthStencilState:_depthStencilState];
    [commandEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [commandEncoder setCullMode:MTLCullModeBack];
    
    [commandEncoder setVertexBuffer:_mesh.vertexBuffer offset:0 atIndex:0];
    
    id<MTLBuffer> sharedDataBuffer = _perFrameData[_frameIndex % cMaxBuffersInFlight].sharedData;
    [commandEncoder setVertexBuffer:sharedDataBuffer offset:0 atIndex:1];
    [commandEncoder setFragmentBuffer:sharedDataBuffer offset:0 atIndex:0];
    
    [commandEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                               indexCount:[_mesh.indexBuffer length] / sizeof(uint16_t)
                                indexType:MTLIndexTypeUInt16
                              indexBuffer:_mesh.indexBuffer
                        indexBufferOffset:0];
    
    [commandEncoder popDebugGroup];
    
    [commandEncoder pushDebugGroup:@"Draw ImGui"];
    
    ImGuiIO &io = ImGui::GetIO();
    io.DeltaTime = 1 / float(view.preferredFramesPerSecond ?: 60);
    ImGui_ImplMetal_NewFrame(renderPassDescriptor);
    
    {
        static float f = 0.0f;
        static int counter = 0;
        ImGui::Text("Hello, world!");                           // Display some text (you can use a format string too)
        ImGui::SliderFloat("float", &f, 0.0f, 1.0f);            // Edit 1 float using a slider from 0.0f to 1.0f
        ImGui::ColorEdit3("clear color", (float*)&clear_color); // Edit 3 floats representing a color
        
        ImGui::Checkbox("Demo Window", &show_demo_window);      // Edit bools storing our windows open/close state
        ImGui::Checkbox("Another Window", &show_another_window);
        
        if (ImGui::Button("Button"))                            // Buttons return true when clicked (NB: most widgets return true when edited/activated)
            counter++;
        ImGui::SameLine();
        ImGui::Text("counter = %d", counter);
        
        ImGui::Text("Application average %.3f ms/frame (%.1f FPS)", 1000.0f / ImGui::GetIO().Framerate, ImGui::GetIO().Framerate);
    }
    
    // 2. Show another simple window. In most cases you will use an explicit Begin/End pair to name your windows.
    if (show_another_window)
    {
        ImGui::Begin("Another Window", &show_another_window);
        ImGui::Text("Hello from another window!");
        if (ImGui::Button("Close Me"))
            show_another_window = false;
        ImGui::End();
    }
    
    // 3. Show the ImGui demo window. Most of the sample code is in ImGui::ShowDemoWindow(). Read its code to learn more about Dear ImGui!
    if (show_demo_window)
    {
        // Normally user code doesn't need/want to call this because positions are saved in .ini file anyway.
        // Here we just want to make the demo initial state a bit more friendly!
        ImGui::SetNextWindowPos(ImVec2(650, 20), ImGuiCond_FirstUseEver);
        ImGui::ShowDemoWindow(&show_demo_window);
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
