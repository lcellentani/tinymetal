#import "Renderer.h"
#import "GraphicsTypes.h"
#import "MathUtils.h"

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
        for (uint32_t i = 0; i < cMaxBuffersInFlight; ++i) {
            _perFrameData[i].sharedData = [_device newBufferWithLength:sizeof(SharedData) options:MTLResourceOptionCPUCacheModeDefault];
        }
        _commandQueue = [_device newCommandQueue];
        
        _inFlightSemaphore = dispatch_semaphore_create(cMaxBuffersInFlight);
        _startupTime = CACurrentMediaTime();
        _lastTime = CACurrentMediaTime();
        _frameIndex = 0;
        _currentTime = 0.0f;
        _rotationX = 0.0f;
        _rotationY = 0.0;
        
        [self makePipelines];
        [self makeBuffers];
    }
    return self;
}

- (void)makePipelines {
    NSError *error = nil;
    
    id<MTLLibrary> library = [_device newDefaultLibrary];
    
    MTLVertexDescriptor *vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];
    vertexDescriptor.attributes[0].format = MTLVertexFormatFloat4;
    vertexDescriptor.attributes[0].bufferIndex = 0;
    vertexDescriptor.attributes[0].offset = 0;
    vertexDescriptor.attributes[1].format = MTLVertexFormatFloat4;
    vertexDescriptor.attributes[1].bufferIndex = 0;
    vertexDescriptor.attributes[1].offset = sizeof(float) * 4;
    vertexDescriptor.layouts[0].stride = sizeof(float) * 8;
    vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    MTLRenderPipelineDescriptor *pipelineDescriptor = [MTLRenderPipelineDescriptor new];
    pipelineDescriptor.vertexFunction = [library newFunctionWithName:@"main_vs"];
    pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"main_fs"];
    pipelineDescriptor.vertexDescriptor = vertexDescriptor;
    pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    
    _renderPipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    NSAssert(_renderPipelineState, @"Error occurred when creating render pipeline state: %@", error);
    
    MTLDepthStencilDescriptor *depthStencilDescriptor = [MTLDepthStencilDescriptor new];
    depthStencilDescriptor.depthCompareFunction = MTLCompareFunctionLess;
    depthStencilDescriptor.depthWriteEnabled = YES;
    _depthStencilState = [_device newDepthStencilStateWithDescriptor:depthStencilDescriptor];
}
    
- (void)makeBuffers {
    static const Vertex vertices[] =
    {
        { .position = { -1,  1,  1, 1 }, .color = { 0, 1, 1, 1 } },
        { .position = { -1, -1,  1, 1 }, .color = { 0, 0, 1, 1 } },
        { .position = {  1, -1,  1, 1 }, .color = { 1, 0, 1, 1 } },
        { .position = {  1,  1,  1, 1 }, .color = { 1, 1, 1, 1 } },
        { .position = { -1,  1, -1, 1 }, .color = { 0, 1, 0, 1 } },
        { .position = { -1, -1, -1, 1 }, .color = { 0, 0, 0, 1 } },
        { .position = {  1, -1, -1, 1 }, .color = { 1, 0, 0, 1 } },
        { .position = {  1,  1, -1, 1 }, .color = { 1, 1, 0, 1 } }
    };
    static const uint32_t verticesCount = sizeof(vertices) / sizeof(Vertex);
    
    static const uint16_t indices[] =
    {
        3, 2, 6, 6, 7, 3,
        4, 5, 1, 1, 0, 4,
        4, 0, 3, 3, 7, 4,
        1, 5, 6, 6, 2, 1,
        0, 1, 2, 2, 3, 0,
        7, 6, 5, 5, 4, 7
    };

    _vertexBuffer = [_device newBufferWithBytes:vertices length:sizeof(vertices) * verticesCount options:MTLResourceOptionCPUCacheModeDefault];
    [_vertexBuffer setLabel:@"Vertices"];
    
    _indexBuffer = [_device newBufferWithBytes:indices length:sizeof(indices) options:MTLResourceOptionCPUCacheModeDefault];
    [_indexBuffer setLabel:@"Indices"];
}
    
- (void)updateSharedData {
    _lastTime = _currentTime;
    _currentTime = CACurrentMediaTime() - _startupTime;
    float elapsed = _currentTime - _lastTime;
    
    _rotationX += elapsed * (M_PI / 2);
    _rotationY += elapsed * (M_PI / 3);
    float scaleFactor = sinf(5.0f * _currentTime) * 0.25f + 1.0f;
    const vector_float3 xAxis = { 1.0f, 0.0f, 0.0f };
    const vector_float3 yAxis = { 0.0f, 1.0f, 0.0f };
    const matrix_float4x4 xRot = matrix_float4x4_rotation(xAxis, _rotationX);
    const matrix_float4x4 yRot = matrix_float4x4_rotation(yAxis, _rotationY);
    const matrix_float4x4 scale = matrix_float4x4_uniform_scale(scaleFactor);
    const matrix_float4x4 modelMatrix = matrix_multiply(matrix_multiply(xRot, yRot), scale);
    
    const vector_float3 cameraTranslation = { 0.0f, 0.0f, -5.0f };
    const matrix_float4x4 viewMatrix = matrix_float4x4_translation(cameraTranslation);
    
    const float aspect = _drawableSize.width / _drawableSize.height;
    const float fov = (2.0f * M_PI) / 5.0f;
    const float near = 1.0f;
    const float far = 100.0f;
    const matrix_float4x4 projectionMatrix = matrix_float4x4_perspective(aspect, fov, near, far);
    
    SharedData data;
    data.u_frameIndex = _frameIndex;
    data.u_time = elapsed;
    data.u_modelViewProjection = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix));
    
    id<MTLBuffer> sharedDataBuffer = _perFrameData[_frameIndex % cMaxBuffersInFlight].sharedData;
    memcpy([sharedDataBuffer contents], &data, sizeof(SharedData));
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
    
    [self updateSharedData];
    
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    if (renderPassDescriptor == nil) {
        [commandBuffer commit];
        return;
    }
    
    id<MTLRenderCommandEncoder> commandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    commandEncoder.label = @"CommandEncoder";
    
    [commandEncoder setRenderPipelineState:_renderPipelineState];
    [commandEncoder setDepthStencilState:_depthStencilState];
    [commandEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [commandEncoder setCullMode:MTLCullModeBack];
    
    [commandEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
    
    id<MTLBuffer> sharedDataBuffer = _perFrameData[_frameIndex % cMaxBuffersInFlight].sharedData;
    [commandEncoder setVertexBuffer:sharedDataBuffer offset:0 atIndex:1];
    
    [commandEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                               indexCount:[_indexBuffer length] / sizeof(uint16_t)
                                indexType:MTLIndexTypeUInt16
                              indexBuffer:_indexBuffer
                        indexBufferOffset:0];
    
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
}
    
@end
