#pragma once

#import <simd/simd.h>

typedef struct {
    vector_float4 position;
    vector_float4 color;
} Vertex;

struct SharedData
{
    unsigned int frameIndex;
    float time;
    
    matrix_float4x4 modelViewProjection;
};
