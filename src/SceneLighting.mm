#import "SceneLighting.h"
#import "ObjMesh.h"
#import "ObjModel.h"
#import "ObjGroup.h"
#import "PositionNormalVertexFormat.h"
#import "MathUtils.h"

#include <vector>

#import <simd/simd.h>

typedef struct {
    simd::float4 position;
    simd::float4 normal;
} Vertex;

typedef struct {
    matrix_float4x4 u_modelViewProjectionMatrix;
    matrix_float4x4 u_modelViewMatrix;
    matrix_float3x3 u_normalMatrix;
} SharedData;

@implementation SceneLighting {
    id<MTLRenderPipelineState> _renderPipelineState;
    id<MTLDepthStencilState> _depthStencilState;
    
    ObjMesh* _mesh;
    
    struct PerFrameData {
        id<MTLBuffer> sharedData;
    };
    std::vector<PerFrameData> _perFrameData;
    
    NSUInteger _inFlightBuffersCount;
    float _rotationX;
    float _rotationY;
}

+ (id<Scene>)newScene {
    return [[SceneLighting alloc] init];
}

- (instancetype)init {
    if (self = [super init]) {
        
    }
    return self;
}

- (void)prepare:(id<MTLDevice>)device inFlightBuffersCount:(NSUInteger)buffersCount {
    NSError *error = nil;
    
    id<MTLLibrary> library = [device newDefaultLibrary];
    
    MTLDepthStencilDescriptor *depthStencilDescriptor = [MTLDepthStencilDescriptor new];
    depthStencilDescriptor.depthCompareFunction = MTLCompareFunctionLess;
    depthStencilDescriptor.depthWriteEnabled = YES;
    _depthStencilState = [device newDepthStencilStateWithDescriptor:depthStencilDescriptor];
    
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
    _renderPipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    NSAssert(_renderPipelineState, @"Error occurred when creating render pipeline state: %@", error);
    
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"teapot" withExtension:@"obj"];
    //NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"monkey" withExtension:@"obj"];
    ObjModel *model = [[ObjModel alloc] initWithContentsOfURL:modelURL generateNormals:YES];
    ObjGroup *group = [model groupForName:@"teapot"];
    //ObjGroup *group = [model groupAtIndex:0];
    
    PositionNormalVertexFormat* vertexFormat = [PositionNormalVertexFormat newVertexFormat:[group verticesCount]];
    _mesh = [[ObjMesh alloc] initWithGroup:group device:device vertexFormat:vertexFormat];
    
    _inFlightBuffersCount = buffersCount;
    _perFrameData.resize(_inFlightBuffersCount);
    for (uint32_t i = 0; i < _inFlightBuffersCount; ++i) {
        _perFrameData[i].sharedData = [device newBufferWithLength:sizeof(SharedData) options:MTLResourceOptionCPUCacheModeDefault];
    }
}

- (void)updateFrame:(NSUInteger)frameIndex elapsedTime:(float)elapsedTime drawableSize:(CGSize)drawableSize {
    _rotationX += elapsedTime * (M_PI / 2);
    _rotationY += elapsedTime * (M_PI / 3);
    float scaleFactor = 0.5f;
    const vector_float3 xAxis = { 1, 0, 0 };
    const vector_float3 yAxis = { 0, 1, 0 };
    const matrix_float4x4 xRot = matrix_float4x4_rotation(xAxis, _rotationX);
    const matrix_float4x4 yRot = matrix_float4x4_rotation(yAxis, _rotationY);
    const matrix_float4x4 scale = matrix_float4x4_uniform_scale(scaleFactor);
    const matrix_float4x4 modelMatrix = matrix_multiply(matrix_multiply(xRot, yRot), scale);
    
    const vector_float3 cameraTranslation = { 0, 0, -1.5 };
    const matrix_float4x4 viewMatrix = matrix_float4x4_translation(cameraTranslation);
    
    const float aspect = drawableSize.width / drawableSize.height;
    const float fov = (2.0f * M_PI) / 5.0f;
    const float near = 0.1f;
    const float far = 100.0f;
    const matrix_float4x4 projectionMatrix = matrix_float4x4_perspective(aspect, fov, near, far);
    
    SharedData data;
    data.u_modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix));
    data.u_modelViewMatrix = matrix_multiply(viewMatrix, modelMatrix);
    data.u_normalMatrix = matrix_float4x4_extract_linear(data.u_modelViewMatrix);
    
    id<MTLBuffer> sharedDataBuffer = _perFrameData[frameIndex % _inFlightBuffersCount].sharedData;
    memcpy([sharedDataBuffer contents], &data, sizeof(SharedData));
}

- (void)renderFrame:(id<MTLDevice>)device commandEncoder:(id<MTLRenderCommandEncoder>)commandEncoder frameIndex:(NSUInteger)frameIndex {
    [commandEncoder setRenderPipelineState:_renderPipelineState];
    [commandEncoder setDepthStencilState:_depthStencilState];
    [commandEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [commandEncoder setCullMode:MTLCullModeBack];
    
    [commandEncoder setVertexBuffer:_mesh.vertexBuffer offset:0 atIndex:0];
    
    id<MTLBuffer> sharedDataBuffer = _perFrameData[frameIndex % _inFlightBuffersCount].sharedData;
    [commandEncoder setVertexBuffer:sharedDataBuffer offset:0 atIndex:1];
    [commandEncoder setFragmentBuffer:sharedDataBuffer offset:0 atIndex:0];
    
    [commandEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                               indexCount:[_mesh.indexBuffer length] / sizeof(uint16_t)
                                indexType:MTLIndexTypeUInt16
                              indexBuffer:_mesh.indexBuffer
                        indexBufferOffset:0];
}

- (NSString *) title {
    return [NSString stringWithUTF8String:"Phong shading"];
}

@end
