#pragma once

#import <simd/simd.h>

typedef struct {
    simd::float4 position;
    simd::float4 color;
} Vertex;

struct SharedData
{
    unsigned int u_frameIndex;
    float u_time;
    
    matrix_float4x4 u_modelViewProjection;
};
