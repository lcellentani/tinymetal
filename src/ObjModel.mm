#import "ObjModel.h"
#import "ObjGroup.h"
#import <simd/simd.h>

#include <vector>
#include <map>
#include <functional>

struct FaceVertex {
    FaceVertex() : vi(0), ti(0), ni(0) {
    }
    
    uint16_t vi, ti, ni;
};

static bool operator <(const FaceVertex &v0, const FaceVertex &v1) {
    if (v0.vi < v1.vi) {
        return true;
    } else if (v0.vi > v1.vi) {
        return false;
    } else if (v0.ti < v1.ti) {
        return true;
    } else if (v0.ti > v1.ti) {
        return false;
    } else if (v0.ni < v1.ni) {
        return true;
    } else if (v0.ni > v1.ni) {
        return false;
    }
    return false;
}

@interface ObjModel ()
{
    std::vector<vector_float4> vertices;
    std::vector<vector_float4> normals;
    std::vector<vector_float2> texcoords;
    
    std::vector<vector_float4> groupPositions;
    std::vector<vector_float4> groupNormals;
    std::vector<vector_float4> groupColors;
    std::vector<vector_float2> groupTexcoords;
    std::vector<uint16_t> groupIndices;
    std::map<FaceVertex, uint16_t> vertexToGroupIndexMap;
}

@property (nonatomic, strong) NSMutableArray *mutableGroups;
@property (nonatomic, weak) ObjGroup *currentGroup;
@property (nonatomic, assign) BOOL shouldGenerateNormals;

@end

@implementation ObjModel

- (instancetype)initWithContentsOfURL:(NSURL *)fileURL generateNormals:(BOOL)generateNormals {
    if ((self = [super init])) {
        _shouldGenerateNormals = generateNormals;
        _mutableGroups = [NSMutableArray array];
        [self parseModelAtURL:fileURL];
    }
    return self;
}

- (NSArray *)groups {
    return [_mutableGroups copy];
}

- (ObjGroup *)groupForName:(NSString *)groupName {
    __block ObjGroup *group = nil;
    [_mutableGroups enumerateObjectsUsingBlock:^(ObjGroup *obj, NSUInteger idx, BOOL *stop) {
         if ([obj.name isEqualToString:groupName]) {
             group = obj;
             *stop = YES;
         }
     }];
    return group;
}

- (ObjGroup *)groupAtIndex:(NSUInteger)index {
    if (index < [_mutableGroups count]) {
        return _mutableGroups[index];
    }
    return nil;
}

#pragma mark -

- (void)parseModelAtURL:(NSURL *)url {
    NSError *error = nil;
    NSString *contents = [NSString stringWithContentsOfURL:url encoding:NSASCIIStringEncoding error:&error];
    if (!contents) {
        return;
    }
    
    NSScanner *scanner = [NSScanner scannerWithString:contents];
    
    NSCharacterSet *skipSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSCharacterSet *consumeSet = [skipSet invertedSet];
    
    scanner.charactersToBeSkipped = skipSet;
    
    NSCharacterSet *endlineCharacters = [NSCharacterSet newlineCharacterSet];
    
    [self beginGroupWithName:@"(unnamed)"];
    
    while (![scanner isAtEnd]) {
        NSString *token = nil;
        if (![scanner scanCharactersFromSet:consumeSet intoString:&token]) {
            break;
        }
        
        if ([token isEqualToString:@"v"]) {
            float x, y, z;
            [scanner scanFloat:&x];
            [scanner scanFloat:&y];
            [scanner scanFloat:&z];
            
            vector_float4 v = { x, y, z, 1 };
            vertices.push_back(v);
        } else if ([token isEqualToString:@"vt"]) {
            float u = 0, v = 0;
            [scanner scanFloat:&u];
            [scanner scanFloat:&v];
            
            vector_float2 vt = { u, v };
            texcoords.push_back(vt);
        } else if ([token isEqualToString:@"vn"]) {
            float nx = 0, ny = 0, nz = 0;
            [scanner scanFloat:&nx];
            [scanner scanFloat:&ny];
            [scanner scanFloat:&nz];
            
            vector_float4 vn = { nx, ny, nz, 0 };
            normals.push_back(vn);
        } else if ([token isEqualToString:@"f"]) {
            std::vector<FaceVertex> faceVertices;
            faceVertices.reserve(4);
            
            while (1) {
                int32_t vi = 0, ti = 0, ni = 0;
                if(![scanner scanInt:&vi]) {
                    break;
                }
                
                if ([scanner scanString:@"/" intoString:NULL]) {
                    [scanner scanInt:&ti];
                    
                    if ([scanner scanString:@"/" intoString:NULL]) {
                        [scanner scanInt:&ni];
                    }
                }
                
                FaceVertex faceVertex;
                
                // OBJ format allows relative vertex references in the form of negative indices, and
                // dictates that indices are 1-based. Below, we simultaneously fix up negative indices
                // and offset everything by -1 to allow 0-based indexing later on.
                
                faceVertex.vi = (vi < 0) ? (vertices.size() + vi - 1) : (vi - 1);
                faceVertex.ti = (ti < 0) ? (texcoords.size() + ti - 1) : (ti - 1);
                faceVertex.ni = (ni < 0) ? (vertices.size() + ni - 1) : (ni - 1);
                
                faceVertices.push_back(faceVertex);
            }
            
            [self addFaceWithFaceVertices:faceVertices];
        } else if ([token isEqualToString:@"g"]) {
            NSString *groupName = nil;
            if ([scanner scanUpToCharactersFromSet:endlineCharacters intoString:&groupName]) {
                [self beginGroupWithName:groupName];
            }
        }
    }
    
    [self endCurrentGroup];
}

- (void)beginGroupWithName:(NSString *)name {
    [self endCurrentGroup];
    
    ObjGroup *newGroup = [[ObjGroup alloc] initWithName:name];
    [self.mutableGroups addObject:newGroup];
    self.currentGroup = newGroup;
}

- (void)endCurrentGroup {
    if (!self.currentGroup) {
        return;
    }
    
    if (self.shouldGenerateNormals) {
        [self generateNormalsForCurrentGroup];
    }
    
    self.currentGroup.verticesCount = (uint32_t)groupPositions.size();
    self.currentGroup.positionData = [NSData dataWithBytes:groupPositions.data() length:sizeof(groupPositions[0]) * groupPositions.size()];
    self.currentGroup.normalData = [NSData dataWithBytes:groupNormals.data() length:sizeof(groupNormals[0]) * groupNormals.size()];
    self.currentGroup.colorData = [NSData dataWithBytes:groupColors.data() length:sizeof(groupColors[0]) * groupColors.size()];
    self.currentGroup.texcoordData = [NSData dataWithBytes:groupTexcoords.data() length:sizeof(groupTexcoords[0]) * groupTexcoords.size()];

    self.currentGroup.indexData = [NSData dataWithBytes:groupIndices.data() length:sizeof(uint16_t) * groupIndices.size()];
    
    groupPositions.clear();
    groupNormals.clear();
    groupColors.clear();
    groupTexcoords.clear();
    groupIndices.clear();
    vertexToGroupIndexMap.clear();
    
    self.currentGroup = nil;
}

- (void)generateNormalsForCurrentGroup {
    static const vector_float4 ZERO = { 0, 0, 0, 0 };
    
    size_t i;
    size_t vertexCount = groupPositions.size();
    for (i = 0; i < vertexCount; ++i) {
        groupNormals[i] = ZERO;
    }
    
    size_t indexCount = groupIndices.size();
    for (i = 0; i < indexCount; i += 3) {
        uint16_t i0 = groupIndices[i];
        uint16_t i1 = groupIndices[i + 1];
        uint16_t i2 = groupIndices[i + 2];
        
        vector_float3 p0 = groupPositions[i0].xyz;
        vector_float3 p1 = groupPositions[i1].xyz;
        vector_float3 p2 = groupPositions[i2].xyz;
        
        vector_float3 cross = vector_cross((p1 - p0), (p2 - p0));
        vector_float4 cross4 = { cross.x, cross.y, cross.z, 0 };
        
        groupNormals[i0] += cross4;
        groupNormals[i1] += cross4;
        groupNormals[i2] += cross4;
    }
    
    for (i = 0; i < vertexCount; ++i) {
        groupNormals[i] = vector_normalize(groupNormals[i]);
    }
}

- (void)addFaceWithFaceVertices:(const std::vector<FaceVertex> &)faceVertices {
    for (size_t i = 0; i < faceVertices.size() - 2; ++i) {
        [self addVertexToCurrentGroup:faceVertices[0]];
        [self addVertexToCurrentGroup:faceVertices[i + 1]];
        [self addVertexToCurrentGroup:faceVertices[i + 2]];
    }
}

- (void)addVertexToCurrentGroup:(FaceVertex)fv {
    static const vector_float4 UP = { 0, 1, 0, 0 };
    static const vector_float2 ZERO2 = { 0, 0 };
    static const vector_float4 RGBA_WHITE = { 1, 1, 1, 1 };
    static const uint16_t INVALID_INDEX = 0xffff;
    
    uint16_t groupIndex;
    auto it = vertexToGroupIndexMap.find(fv);
    if (it != vertexToGroupIndexMap.end()) {
        groupIndex = (*it).second;
    } else {
        simd_float4 p = vertices[fv.vi];
        simd_float4 n = (fv.ni != INVALID_INDEX) ? normals[fv.ni] : UP;
        simd_float4 c = RGBA_WHITE;
        simd_float2 t = (fv.ti != INVALID_INDEX) ? texcoords[fv.ti] : ZERO2;
        
        groupPositions.push_back(p);
        groupNormals.push_back(n);
        groupColors.push_back(c);
        groupTexcoords.push_back(t);
        groupIndex = groupPositions.size() - 1;
        vertexToGroupIndexMap[fv] = groupIndex;
    }
    
    groupIndices.push_back(groupIndex);
}


@end
