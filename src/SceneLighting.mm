#import "SceneLighting.h"
#import "ObjMesh.h"
#import "ObjModel.h"
#import "ObjGroup.h"
#import "PositionNormalVertexFormat.h"
#import "MathUtils.h"
#import <simd/simd.h>

#include <vector>
#include "imgui.h"

static vector_float3 _initialPosition{ 0.0f, 0.0f, -2.0f };

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

    float _translation[3];
    float _rotation[3];
    float _scale;
    float _cameraPosition[3];
    bool _animating;
}

+ (id<Scene>)newScene {
    return [[SceneLighting alloc] init];
}

- (instancetype)init {
    if (self = [super init]) {
        
    }
    return self;
}

- (void)prepareUsingRenderer:(Renderer *)renderer {
    if (renderer.device == nil) {
        return;
    }
    
    NSError *error = nil;
    id<MTLLibrary> library = [renderer.device newDefaultLibrary];
    
    MTLDepthStencilDescriptor *depthStencilDescriptor = [MTLDepthStencilDescriptor new];
    depthStencilDescriptor.depthCompareFunction = MTLCompareFunctionLess;
    depthStencilDescriptor.depthWriteEnabled = YES;
    _depthStencilState = [renderer.device newDepthStencilStateWithDescriptor:depthStencilDescriptor];
    
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
    _renderPipelineState = [renderer.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    NSAssert(_renderPipelineState, @"Error occurred when creating render pipeline state: %@", error);
    
    //NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"bv2" withExtension:@"obj"];
    //NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"teapot" withExtension:@"obj"];
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"monkey" withExtension:@"obj"];
    ObjModel *model = [[ObjModel alloc] initWithContentsOfURL:modelURL generateNormals:YES];
    //ObjGroup *group = [model groupForName:@"BV"];
    ObjGroup *group = [model groupForName:@"monkey"];
    //ObjGroup *group = [model groupForName:@"teapot"];
    //ObjGroup *group = [model groupAtIndex:0];
    
    PositionNormalVertexFormat* vertexFormat = [PositionNormalVertexFormat newVertexFormat:[group verticesCount]];
    _mesh = [[ObjMesh alloc] initWithGroup:group device:renderer.device vertexFormat:vertexFormat];
    
    _inFlightBuffersCount = renderer.inFlightBuffersCount;
    _perFrameData.resize(_inFlightBuffersCount);
    for (uint32_t i = 0; i < _inFlightBuffersCount; ++i) {
        _perFrameData[i].sharedData = [renderer.device newBufferWithLength:sizeof(SharedData) options:MTLResourceOptionCPUCacheModeDefault];
    }
    
    [self resetModel];
    
    _cameraPosition[0] = 0.0f;
    _cameraPosition[1] = 0.0f;
    _cameraPosition[2] = 0.0;
    
    _animating = false;
}

- (void)updateFrame:(NSUInteger)frameIndex elapsedTime:(float)elapsedTime drawableSize:(CGSize)drawableSize {
    if (_animating) {
        _rotation[0] += elapsedTime * (M_PI / 2);
        _rotation[1] += elapsedTime * (M_PI / 3);
    }
    const vector_float3 xAxis = { 1, 0, 0 };
    const vector_float3 yAxis = { 0, 1, 0 };
    const vector_float3 zAxis = { 0, 0, 1 };
    const matrix_float4x4 xRot = matrix_float4x4_rotation(xAxis, _rotation[0]);
    const matrix_float4x4 yRot = matrix_float4x4_rotation(yAxis, _rotation[1]);
    const matrix_float4x4 zRot = matrix_float4x4_rotation(zAxis, _rotation[2]);
    const vector_float3 position = { _translation[0], _translation[1], _translation[2] };
    const matrix_float4x4 T = matrix_float4x4_translation(position);
    const matrix_float4x4 R = matrix_multiply(zRot, matrix_multiply(xRot, yRot));
    const matrix_float4x4 S = matrix_float4x4_uniform_scale(_scale);
    const matrix_float4x4 modelMatrix = matrix_multiply(T, matrix_multiply(R, S));
    
    const vector_float3 cameraTranslation = { _cameraPosition[0], _cameraPosition[1], _cameraPosition[2] };
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

- (void) renderDebugFrame:(CGSize)drawableSize {
    ImGui::SetNextWindowPos(ImVec2(5.0f, 50.0f), ImGuiSetCond_FirstUseEver);
    ImGui::Begin([self.title UTF8String], nullptr, ImVec2(drawableSize.width * 0.5f, drawableSize.height * 0.1f), -1.f, ImGuiWindowFlags_AlwaysAutoResize);
    
    ImGui::DragFloat3("translation", _translation, 0.1f);
    ImGui::DragFloat3("rotation", _rotation, 0.01f);
    ImGui::DragFloat("scale", &_scale, 0.001f, 0.0f, 0.0f);
    if (ImGui::Button("reset")) {
        [self resetModel];
    }
    ImGui::SameLine();
    if (ImGui::Button(_animating ? "stop" : "play")) {
        _animating = !_animating;
    }
    
    ImGui::Separator();
    ImGui::DragFloat3("camera pos", _cameraPosition, 0.01f);
    
    ImGui::End();
}

-(void) resetModel {
    _scale = 1.0f;
    
    _translation[0] = _initialPosition.x;
    _translation[1] = _initialPosition.y;
    _translation[2] = _initialPosition.z;
    
    _rotation[0] = 0.0f;
    _rotation[1] = 0.0f;
    _rotation[2] = 0.0f;
}

@end
