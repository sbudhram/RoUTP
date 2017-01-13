//
//  ROUDataTypes.h
//  RoUTPTests
//
//  Created by Yan Rabovik on 30.06.13.
//  Copyright (c) 2013 Yan Rabovik. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ROUPrivate.h"

#define ROU_PLAYER_SIZE         64  //Size of a GKCloudPlayerID
#define ROU_HEADER_SIZE         (sizeof(ROUChunkHeader))

#pragma mark - Structures -
typedef NS_ENUM(uint8_t, ROUChunkType){
    ROUChunkTypeData = 0,
    ROUChunkTypeAck = 1,
    ROUChunkUnreliable = 2
};
typedef NS_OPTIONS(uint8_t, ROUAckFlags){
    ROUAckFlagsNone = 0,
    ROUAckFlagsHasSegments = 1 << 0
};

typedef struct {
    char playerID[ROU_PLAYER_SIZE];
    u_int32_t tsn;
} Player;

typedef struct {
    uint8_t type;
    uint8_t flags;
    Player sender;
    Player receiver0;
    Player receiver1;
    Player receiver2;
    uint16_t length;
} ROUChunkHeader;

ROUChunkHeader ROUChunkHeaderMake(ROUChunkType type, uint8_t flags, uint16_t length);
ROUChunkHeader ROUChunkHeaderAddFlag(ROUChunkHeader header, uint8_t flag);

typedef struct {
    uint16_t start;
    uint16_t end;
} ROUAckSegmentShift;

ROUAckSegmentShift ROUAckSegmentShiftMake(uint16_t start, uint16_t end);

bool ROUAckSegmentShiftsEqual(ROUAckSegmentShift segmentShift1,
                              ROUAckSegmentShift segmentShift2);

#pragma mark - Classes -
#pragma mark Common chunks
@interface ROUChunk : NSObject
+(id)chunkWithEncodedChunk:(NSData *)encodedChunk;
@property (nonatomic,readonly) ROUChunkHeader header;
@property (nonatomic,readonly) NSData *encodedChunk;
@end

#pragma mark Data chunk
@interface ROUDataChunk : ROUChunk
/**
 @param tsn Transmission Sequence Number
 */
+(id)chunkWithData:(NSData *)data TSN:(uint32_t)tsn sender:(NSString*)sender recipients:(NSArray<NSString*>*)recipients;
+(id)unreliableChunkWithData:(NSData *)data sender:(NSString*)sender recipients:(NSArray<NSString*>*)recipients;
@property (nonatomic,readonly) NSData *data;
@end

@interface ROUSndDataChunk : ROUDataChunk
@property (nonatomic,strong) NSDate *lastSendDate;
@property (nonatomic) NSUInteger resendCount;
@end

#pragma mark Ack chunk
@interface ROUAckChunk : ROUChunk
+(id)chunkWithTSN:(uint32_t)tsn;
-(void)addSegmentFrom:(uint32_t)fromTSN to:(uint32_t)toTSN;
-(void)addSegmentWithRange:(NSRange)range;
-(NSIndexSet *)segmentsIndexSet;
-(NSIndexSet *)missedIndexSet;
@end

#pragma mark - Categories -
@interface NSValue (ROUAckSegmentShift)
+(NSValue *)rou_valueWithAckSegmentShift:(ROUAckSegmentShift)segmentShift;
-(ROUAckSegmentShift)rou_ackSegmentShift;
@end
