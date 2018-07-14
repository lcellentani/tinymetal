#import "Mesh.h"

@class ObjGroup;

@interface ObjMesh : Mesh

- (instancetype)initWithGroup:(ObjGroup *)group device:(id<MTLDevice>)device;

@end
