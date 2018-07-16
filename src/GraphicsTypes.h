#pragma once

#import <simd/simd.h>

typedef struct {
    simd::float4 position;
    simd::float4 normal;
} Vertex;

typedef struct {
    unsigned int u_frameIndex;
    float u_time;
    matrix_float4x4 u_modelViewProjectionMatrix;
    matrix_float4x4 u_modelViewMatrix;
    matrix_float3x3 u_normalMatrix;
} SharedData;
