#import "ObjGroup.h"

@implementation ObjGroup

- (instancetype)initWithName:(NSString *)name {
    if ((self = [super init])) {
        _name = [name copy];
    }
    return self;
}

- (NSString *)description {
    size_t vertCount = self.positionData.length;
    size_t indexCount = self.indexData.length / sizeof(uint16_t);
    return [NSString stringWithFormat:@"<ObjGroup %p> (\"%@\", %d vertices, %d indices)", self, self.name, (int)vertCount, (int)indexCount];
}

@end
