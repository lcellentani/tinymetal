#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float4 a_position [[attribute(0)]];
    half4 a_color [[attribute(1)]];
};

struct VertexOut {
    float4 gl_Position [[position]];
    half4 v_color;
};

struct SharedData {
    unsigned int u_frameIndex;
    float u_time;
    float4x4 u_modelViewProjection;
};

vertex VertexOut main_vs(VertexIn vin[[stage_in]],
                      constant SharedData& sharedData[[buffer(1)]]) {
    VertexOut vout;
    vout.gl_Position = sharedData.u_modelViewProjection * vin.a_position;
    vout.v_color = vin.a_color;
    
    return vout;
}

fragment half4 main_fs(VertexOut vout[[stage_in]]) {
    return vout.v_color;
}
