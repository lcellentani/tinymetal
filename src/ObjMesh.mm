#import "ObjMesh.h"
#import "ObjGroup.h"
#import <simd/simd.h>

#include <vector>

@implementation ObjMesh

@synthesize indexBuffer=_indexBuffer;
@synthesize vertexBuffer=_vertexBuffer;

- (instancetype)initWithGroup:(ObjGroup *)group device:(id<MTLDevice>)device {
    if ((self = [super init])) {
        struct Vertex {
            Vertex(simd_float4 p, simd_float4 n) : position(p), normal(n) {}
            simd_float4 position;
            simd_float4 normal;
        };
        std::vector<Vertex> data;
        simd_float4* positions = (simd_float4*)[group.positionData bytes];
        simd_float4* normals = (simd_float4*)[group.normalData bytes];
        for(size_t i = 0; i < (size_t)group.verticesCount; i++) {
            data.emplace_back(positions[i], normals[i]);
        }
        
        _vertexBuffer = [device newBufferWithBytes:data.data()
                                            length:sizeof(data[0]) * data.size()
                                           options:MTLResourceOptionCPUCacheModeDefault];
        [_vertexBuffer setLabel:[NSString stringWithFormat:@"Vertices (%@)", group.name]];
        
        _indexBuffer = [device newBufferWithBytes:[group.indexData bytes]
                                           length:[group.indexData length]
                                          options:MTLResourceOptionCPUCacheModeDefault];
        [_indexBuffer setLabel:[NSString stringWithFormat:@"Indices (%@)", group.name]];
    }
    return self;
}

@end

