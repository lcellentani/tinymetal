#import <Foundation/Foundation.h>

@class ObjGroup;

@interface ObjModel : NSObject

@property (nonatomic, readonly) NSArray *groups;

- (instancetype)initWithContentsOfURL:(NSURL *)fileURL generateNormals:(BOOL)generateNormals;

- (ObjGroup *)groupForName:(NSString *)groupName;
- (ObjGroup *)groupAtIndex:(NSUInteger)index;

@end
