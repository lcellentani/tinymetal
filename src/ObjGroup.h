#import <Foundation/Foundation.h>

@interface ObjGroup : NSObject

@property (copy) NSString *name;
@property (nonatomic) uint32_t verticesCount;
@property (copy) NSData *positionData;
@property (copy) NSData *normalData;
@property (copy) NSData *texcoordData;
@property (copy) NSData *colorData;
@property (copy) NSData *indexData;

- (instancetype)initWithName:(NSString *)name;

@end
