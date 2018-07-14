#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

@interface Mesh : NSObject

@property (nonatomic, readonly) id<MTLBuffer> vertexBuffer;
@property (nonatomic, readonly) id<MTLBuffer> indexBuffer;

@end
