#import <Foundation/Foundation.h>

@protocol VertexFormat<NSObject>

@required
- (void)setPositionBytes:(const void *)data lenght:(NSUInteger)lenght;

- (NSData *)encode;

@optional
- (void)setNormalBytes:(const void *)data lenght:(NSUInteger)lenght;
- (void)setTexcoords:(const void *)data lenght:(NSUInteger)lenght;
- (void)setColors:(const void *)data lenght:(NSUInteger)lenght;


@end
