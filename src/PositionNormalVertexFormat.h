#import "VertexFormat.h"

@interface PositionNormalVertexFormat : NSObject<VertexFormat>

+ (id<VertexFormat>)newVertexFormat:(NSUInteger)size;

- (instancetype)initWithSize:(NSUInteger)size;

- (void)setPositionBytes:(const void *)data lenght:(NSUInteger)lenght;
- (void)setNormalBytes:(const void *)data lenght:(NSUInteger)lenght;

- (NSData *)encode;

@end
