#import "Mesh.h"
#import "VertexFormat.h"

@class ObjGroup;

@interface ObjMesh : Mesh

- (instancetype)initWithGroup:(ObjGroup *)group device:(id<MTLDevice>)device vertexFormat:(id<VertexFormat>)vertexFormat;

@end
