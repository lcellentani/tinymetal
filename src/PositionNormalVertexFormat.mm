#import "PositionNormalVertexFormat.h"
#import <simd/simd.h>

#include <vector>

@implementation PositionNormalVertexFormat {
    struct _vertex{
        _vertex() = default;
        _vertex(simd_float4 p, simd_float4 n) : position(p), normal(n) {}
        
        simd_float4 position;
        simd_float4 normal;
    };
    
    std::vector<_vertex> vertexData;
}

+ (id<VertexFormat>)newVertexFormat:(NSUInteger)size {
    return [[PositionNormalVertexFormat alloc] initWithSize:size];
}

- (id)initWithSize:(NSUInteger)size {
    if (self = [super init]) {
        vertexData.clear();
        vertexData.resize(size);
    }
    return self;
}

- (void)setPositionBytes:(const void *)data lenght:(NSUInteger)lenght {
    size_t count = (size_t)lenght / sizeof(simd_float4);
    if (count <= vertexData.size()) {
        simd_float4* ptr = (simd_float4*)data;
        for(size_t i = 0; i < count; i++) {
            vertexData[i].position = ptr[i];
        }
    }
}

- (void)setNormalBytes:(const void *)data lenght:(NSUInteger)lenght {
    size_t count = (size_t)lenght / sizeof(simd_float4);
    if (count <= vertexData.size()) {
        simd_float4* ptr = (simd_float4*)data;
        for(size_t i = 0; i < count; i++) {
            vertexData[i].normal = ptr[i];
        }
    }
}

- (NSData *)encode {
    if (!vertexData.empty()) {
        return [NSData dataWithBytes:vertexData.data() length:(sizeof(vertexData[0]) * vertexData.size())];
    }
    return nil;
    
}

@end
