#include <metal_stdlib>
using namespace metal;

#include "GraphicsTypes.h"

struct VertexIn {
    float4 position;
    float4 color;
};

struct VertexOut {
    float4 position [[position]];
    half4 color;
};

vertex VertexOut main_vs(device VertexIn* vertices[[buffer(0)]],
                      constant SharedData* sharedData[[buffer(1)]],
                      uint vid [[vertex_id]]) {
    VertexOut vertexOut;
    vertexOut.position = sharedData->modelViewProjection * vertices[vid].position;
    vertexOut.color = (half4)vertices[vid].color;
    
    return vertexOut;
}

fragment half4 main_fs(VertexOut vertexIn [[stage_in]]) {
    return half4(vertexIn.color);
}
