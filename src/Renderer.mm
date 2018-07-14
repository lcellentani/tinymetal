#import "Renderer.h"
#import "GraphicsTypes.h"
#import "MathUtils.h"
#import "ObjMesh.h"
#import "ObjModel.h"

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
    _mesh = [[ObjMesh alloc] initWithGroup:group device:_device];
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
    
    [commandEncoder setVertexBuffer:_mesh.vertexBuffer offset:0 atIndex:0];
    
    id<MTLBuffer> sharedDataBuffer = _perFrameData[_frameIndex % cMaxBuffersInFlight].sharedData;
    [commandEncoder setVertexBuffer:sharedDataBuffer offset:0 atIndex:1];
    
    [commandEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                               indexCount:[_mesh.indexBuffer length] / sizeof(uint16_t)
                                indexType:MTLIndexTypeUInt16
                              indexBuffer:_mesh.indexBuffer
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
