//
//  ROUDataTypes.h
//  RoUTPTests
//
//  Created by Yan Rabovik on 30.06.13.
//  Copyright (c) 2013 Yan Rabovik. All rights reserved.
//

//ORIGINAL MESSAGE:
// - Sent from 'sender' instance
// - 'tsn' is the 'global' tsn for the sender
// - recipients each have their own 'tsn'
// - chunks are stored, referenced by the global tsn

//RECEIVED MESSAGES:
// - Received in the instance repesenting the sender
// - uses only the recipient's tsn for local tracking
// - sends back acknowledgements in the form of the recipient's tsn.
// - Uses global tsn variable location, sender/recipient tsn slot not used.

//RECEIVED ACKNOWLEDGEMENTS
// - TSN received represents receiver's TSN, not the global one.
// - Need to reverse-lookup based on this TSN to get the correct instances
// - Modify/remove instances based on whether all players for the message have received it.

//RESENDING
// - Resend on a specific interval, not just whenever receiving a message.

//Maybe we need to get rid of the individual TSN, and just use the recipient TSN.
//Have the tracking on the sender be in relation to the individual recipient TSNs.
//When triaging acknowledgements, just check for the given recipient, remove if needed for theirs.
//When figuring out whether to resend, just iterate on all, group and send.
//
//- Easier to remove players, because we can just delete their respective array entries, and it'll stop trying to resend.

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

//For data sent, TSN is with the receiver.
//For acknowledgements, TSN is with the sender.
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
NS_RETURNS_RETAINED NSString *senderForHeader(ROUChunkHeader header);

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
-(void)setSender:(NSString*)sender tsn:(u_int32_t)tsn;
-(void)setRecipient:(NSString*)recipient tsn:(u_int32_t)tsn index:(NSUInteger)index;
-(NSNumber*)tsnForPlayer:(NSString*)player;
@end

#pragma mark Data chunk
@interface ROUDataChunk : ROUChunk
+(id)chunkWithData:(NSData *)data;
@property (nonatomic,readonly) NSData *data;
@end

@interface ROUSndDataChunk : ROUDataChunk
@property (nonatomic,strong) NSDate *lastSendDate;
@property (nonatomic) NSUInteger resendCount;
@end

#pragma mark Ack chunk
@interface ROUAckChunk : ROUChunk
+(id)chunk;
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
