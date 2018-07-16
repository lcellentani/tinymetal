#import "ObjMesh.h"
#import "ObjGroup.h"
#import <simd/simd.h>

#include <vector>

@implementation ObjMesh

@synthesize indexBuffer=_indexBuffer;
@synthesize vertexBuffer=_vertexBuffer;

- (instancetype)initWithGroup:(ObjGroup *)group device:(id<MTLDevice>)device vertexFormat:(id<VertexFormat>)vertexFormat {
    if ((self = [super init])) {
        [vertexFormat setPositionBytes:[group.positionData bytes] lenght:[group.positionData length]];
        [vertexFormat setNormalBytes:[group.normalData bytes] lenght:[group.normalData length]];
        NSData* vertexData = [vertexFormat encode];
        
        _vertexBuffer = [device newBufferWithBytes:[vertexData bytes]
                                            length:[vertexData length]
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

