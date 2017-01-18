//
//  ROUDataTypes.m
//  RoUTPTests
//
//  Created by Yan Rabovik on 30.06.13.
//  Copyright (c) 2013 Yan Rabovik. All rights reserved.
//

#import "ROUDataTypes.h"
#import "ROUPrivate.h"

#if !__has_feature(objc_arc)
#error This code needs ARC. Use compiler option -fobjc-arc
#endif

#pragma mark - Structures -
ROUChunkHeader ROUChunkHeaderMake(ROUChunkType type, uint8_t flags, uint16_t length) {
    ROUChunkHeader header;
    header.type = type;
    header.flags = flags;
    header.length = length;
    
    return header;
}

void setSender(ROUChunkHeader *header, NSString *sender, u_int32_t tsn) {

    NSCAssert(sender != nil, @"Sender must be specified");
    NSCAssert(sender.length <= ROU_PLAYER_SIZE, @"GKCloudPlayerID must be less than %d characters <sender>", ROU_PLAYER_SIZE);
    
    const char *sndr = [sender UTF8String];
    strncpy(header->sender.playerID, sndr, sender.length);
    header->sender.tsn = tsn;
}

void setRecipient(ROUChunkHeader *header, NSString *recipient, u_int32_t tsn, u_int8_t index) {

    NSCAssert(recipient != nil, @"Recipient must be specified");
    NSCAssert(recipient.length <= ROU_PLAYER_SIZE, @"GKCloudPlayerID must be less than %d characters <sender>", ROU_PLAYER_SIZE);
    
    const char *rcpt = [recipient UTF8String];
    switch (index) {
        case 0:
            strncpy(header->receiver0.playerID, rcpt, recipient.length);
            header->receiver0.tsn = tsn;
            break;
            
        case 1:
            strncpy(header->receiver1.playerID, rcpt, recipient.length);
            header->receiver1.tsn = tsn;
            break;
            
        case 2:
            strncpy(header->receiver2.playerID, rcpt, recipient.length);
            header->receiver2.tsn = tsn;
            break;
            
        default:
            break;
    }
}

NS_RETURNS_RETAINED NSString *senderForHeader(ROUChunkHeader header) {
    return [NSString stringWithUTF8String:header.sender.playerID];
}


ROUChunkHeader ROUChunkHeaderAddFlag(ROUChunkHeader header, uint8_t flag){
    ROUChunkHeader newHeader = header;
    newHeader.flags = header.flags | flag;
    return newHeader;
}

ROUAckSegmentShift ROUAckSegmentShiftMake(uint16_t start, uint16_t end){
    ROUAckSegmentShift segment;
    segment.start = start;
    segment.end = end;
    return segment;
}

bool ROUAckSegmentShiftsEqual(ROUAckSegmentShift segmentShift1,
                              ROUAckSegmentShift segmentShift2)
{
    return  segmentShift1.start == segmentShift2.start &&
            segmentShift1.end   == segmentShift2.end;
}

#pragma mark - Classes -
#pragma mark Common chunks
@interface ROUChunk (){
    @protected
    NSData *_encodedChunk;
}
@property (nonatomic,strong) NSData *encodedChunk;
@property (nonatomic,readwrite) ROUChunkHeader header;
@end

@implementation ROUChunk

+(id)chunkWithEncodedChunk:(NSData *)encodedChunk{
    ROUThrow(@"+[%@ %@] not implemented",
             NSStringFromClass(self),
             NSStringFromSelector(_cmd));
    return nil;
}

-(NSData *)encodedChunk{
    ROUThrow(@"-[%@ %@] not implemented",
             NSStringFromClass([self class]),
             NSStringFromSelector(_cmd));
    return nil;
}

-(NSNumber*)tsnForPlayer:(NSString*)player {

    NSString *rcpt = [NSString stringWithUTF8String:_header.receiver0.playerID];
    if ([rcpt isEqualToString:player]) {
        return @(_header.receiver0.tsn);
    }
    
    rcpt = [NSString stringWithUTF8String:_header.receiver1.playerID];
    if ([rcpt isEqualToString:player]) {
        return @(_header.receiver1.tsn);
    }
    
    rcpt = [NSString stringWithUTF8String:_header.receiver2.playerID];
    if ([rcpt isEqualToString:player]) {
        return @(_header.receiver2.tsn);
    }
    
    rcpt = [NSString stringWithUTF8String:_header.sender.playerID];
    if ([rcpt isEqualToString:player]) {
        return @(_header.sender.tsn);
    }
    
    return nil;

}

@end

#pragma mark Data chunk
@interface ROUDataChunk ()
@property (nonatomic,strong) NSData *data;
@end

@implementation ROUDataChunk
+(id)chunkWithEncodedChunk:(NSData *)encodedChunk{
    if (encodedChunk.length <= ROU_HEADER_SIZE) {
        ROUThrow(@"Encoded data chunk is too short");
    }
    ROUDataChunk *chunk = [self new];
    chunk.encodedChunk = encodedChunk;
    
    ROUChunkHeader header;
    [encodedChunk getBytes:&header range:NSMakeRange(0, ROU_HEADER_SIZE)];
    chunk.header = header;

    return chunk;
}
+(id)chunkWithData:(NSData *)data {
    if (data.length > UINT16_MAX - ROU_HEADER_SIZE) {
        ROUThrow(@"Data in chunk may not be longer than %lu bytes", UINT16_MAX - ROU_HEADER_SIZE);
    }
    ROUDataChunk *chunk = [self new];
    chunk.header = ROUChunkHeaderMake(ROUChunkTypeData, 0, data.length + ROU_HEADER_SIZE);
    chunk.data = data;
    return chunk;
}

-(NSData *)encodedChunk{
    if (nil != self->_encodedChunk) {
        return _encodedChunk;
    }
    NSAssert(nil != self.data, @"");
    NSMutableData *chunk = [NSMutableData dataWithCapacity:ROU_HEADER_SIZE + self.data.length];
    ROUChunkHeader header = self.header;
    [chunk appendBytes:&header length:ROU_HEADER_SIZE];
    [chunk appendData:_data];
    return chunk;
}
-(NSData *)data{
    if (nil != _data) {
        return _data;
    }
    NSAssert(nil != self.encodedChunk, @"");
    return [self.encodedChunk
            subdataWithRange:NSMakeRange(ROU_HEADER_SIZE, self.encodedChunk.length-ROU_HEADER_SIZE)];
}
@end

@implementation ROUSndDataChunk
@end

#pragma mark Ack chunk
@interface ROUAckChunk ()
@end

@implementation ROUAckChunk{
    NSMutableIndexSet *_segmentsIndexSet;
}

+(id)chunk{
    ROUAckChunk *chunk = [self new];
    ROUChunkHeaderMake(ROUChunkTypeAck, 0, 0);
    
    return chunk;
}

+(id)chunkWithEncodedChunk:(NSData *)encodedChunk{
    if (encodedChunk.length < ROU_HEADER_SIZE) {
        ROUThrow(@"Encoded ack chunk is too short");
    }
    ROUAckChunk *chunk = [self new];
    chunk.encodedChunk = encodedChunk;
    
    ROUChunkHeader header;
    [encodedChunk getBytes:&header range:NSMakeRange(0, ROU_HEADER_SIZE)];
    
    if (header.flags & ROUAckFlagsHasSegments) {
        NSUInteger currentPosition = ROU_HEADER_SIZE;
        while (currentPosition + 4 <= header.length) {
            ROUAckSegmentShift segmentShift;
            [encodedChunk getBytes:&segmentShift range:NSMakeRange(currentPosition, 4)];
            NSRange range =
                NSMakeRange(header.sender.tsn+segmentShift.start,
                            segmentShift.end - segmentShift.start + 1);
            [chunk->_segmentsIndexSet
                addIndexesInRange:range];
            currentPosition += 4;
        }
    }
    
    return chunk;
}

-(id)init{
    self = [super init];
    if (nil == self) return nil;
	_segmentsIndexSet = [NSMutableIndexSet indexSet];
	return self;
}

-(NSString *)description{
    return [NSString stringWithFormat:@"<%@ %p> header.type=%u header.flags=%u header.length=%u TSN=%u segments=%@ encodedChunk=%@",
            NSStringFromClass([self class]),
            self,
            self.header.type,
            self.header.flags,
            self.header.length,
            self.header.sender.tsn,
            _segmentsIndexSet,
            _encodedChunk];
}

-(void)addSegmentFrom:(uint32_t)fromTSN to:(uint32_t)toTSN{
    NSAssert(fromTSN > self.header.sender.tsn + 1,
             @"tsn=%u fromTSN=%u toTSN=%u",
             self.header.sender.tsn,
             fromTSN,
             toTSN);
    NSAssert(toTSN >= fromTSN,
             @"tsn=%u fromTSN=%u toTSN=%u",
             self.header.sender.tsn,
             fromTSN,
             toTSN);
    [self addSegmentWithRange:NSMakeRange(fromTSN, toTSN-fromTSN+1)];
}

-(void)addSegmentWithRange:(NSRange)range{
    NSAssert(range.location > self.header.sender.tsn + 1,
             @"tsn=%u %@",
             self.header.sender.tsn,
             NSStringFromRange(range));
    NSAssert(range.length > 0,
             @"tsn=%u %@",
             self.header.sender.tsn,
             NSStringFromRange(range));
    _encodedChunk = nil;
    [_segmentsIndexSet addIndexesInRange:range];
}


-(NSIndexSet *)segmentsIndexSet{
    return _segmentsIndexSet;
}

-(NSIndexSet *)missedIndexSet{
    if (_segmentsIndexSet.firstIndex <= self.header.sender.tsn + 1) {
        ROUThrow(@"In ack chunkTSN should be lower than segments.\n%@",self);
    }
    NSMutableIndexSet *missed = [NSMutableIndexSet indexSet];
    __block NSUInteger start = self.header.sender.tsn + 1;
    [_segmentsIndexSet enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
        NSUInteger end = range.location - 1;
        [missed addIndexesInRange:NSMakeRange(start, end-start+1)];
        start = range.length + range.location;
    }];
    return missed;
}

-(NSData *)encodedChunk{
    if (nil != _encodedChunk) {
        return _encodedChunk;
    }
    ROUChunkHeader header = self.header;
    NSMutableData *encodedChunk = [NSMutableData dataWithCapacity:header.length];
    [encodedChunk appendBytes:&header length:ROU_HEADER_SIZE];
    NSAssert(4 == sizeof(ROUAckSegmentShift), @"ROUAckSegmentShift size should be 4");
    [_segmentsIndexSet enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
        ROUAckSegmentShift segment =
            ROUAckSegmentShiftMake(range.location-self.header.sender.tsn,
                                   range.location-self.header.sender.tsn+range.length-1);
        [encodedChunk appendBytes:&segment length:4];
    }];
    return encodedChunk;
}

@end

#pragma mark - Categories -
@implementation NSValue (ROUAckSegmentShift)

+(NSValue *)rou_valueWithAckSegmentShift:(ROUAckSegmentShift)segment{
    return [NSValue valueWithBytes:&segment objCType:@encode(ROUAckSegmentShift)];
}

-(ROUAckSegmentShift)rou_ackSegmentShift{
    ROUAckSegmentShift segment;
    [self getValue:&segment];
    return segment;
}

@end
