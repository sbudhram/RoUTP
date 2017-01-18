//
//  ROUSession.m
//  RoUTPTests
//
//  Created by Yan Rabovik on 27.06.13.
//  Copyright (c) 2013 Yan Rabovik. All rights reserved.
//

#import "ROUSession.h"
#import "ROUSession_Private.h"

#if !__has_feature(objc_arc)
#error This code needs ARC. Use compiler option -fobjc-arc
#endif

@implementation ROUSession{
}

+(ROUChunkHeader)headerForIncomingData:(NSData*)data {
    
    NSUInteger packetLength = data.length;
    NSUInteger currentPosition = 0;
    ROUChunkHeader header;
    [data getBytes:&header range:NSMakeRange(currentPosition, ROU_HEADER_SIZE)];
    if (currentPosition + header.length > packetLength) {
        ROUThrow(@"Incorrect chunk length");
    }

    return header;
    
}

#pragma mark Init
-(id)initWithLocalPlayer:(NSString*)localPlayer sender:(NSString*)sender {
    self = [super init];
    if (nil == self) return nil;
    
    self.localPlayer = localPlayer;
    self.sender = sender;
    
    _sendNextTSNpp = [NSMutableDictionary dictionaryWithCapacity:3];
    
    _rcvNextTSN = 1;
    _rcvDataChunks = [NSMutableDictionary dictionaryWithCapacity:50];
    _rcvDataChunkIndexSet = [NSMutableIndexSet indexSet];
    _sndDataChunks = [NSMutableDictionary dictionaryWithCapacity:3];
    _sndDataChunkIndexSet = [NSMutableDictionary dictionaryWithCapacity:3];
    
    _queue = dispatch_queue_create("com.rabovik.routp.session",NULL);
    
    _rcvAckTimerInterval = ROU_RCV_ACK_TIMER_INTERVAL;
    _rcvAckTimerDelayOnMissed = ROU_RCV_ACK_TIMER_DELAY_ON_MISSED;
    _sndResendTimeout = ROU_SND_RESEND_TIMEOUT;
    _rcvAckTimerTimeout = ROU_RCV_ACK_TIMER_TIMEOUT;
    
    [self resetAckTimeoutTimer];
    
	return self;
}

-(void)dealloc{

    rou_dispatch_release(_queue);
    if (nil != _delegateQueue) {
        rou_dispatch_release(_delegateQueue);
    }
    
}

#pragma mark Main API
-(void)start{
    dispatch_async(self.queue, ^{
        [self scheduleAckTimer];
    });
}

#pragma mark └ Input data
-(void)sendData:(NSData *)data from:(NSString*)sender to:(NSArray<NSString*>*)recipients reliably:(BOOL)reliable immediately:(BOOL)immediately {

    void (^send)(void) = ^{
        if (reliable) {
            [self scheduleAckTimer];
        }
        [self input_sendData:data from:sender to:recipients reliably:reliable immediately:immediately];
    };
    
    if (immediately) {
        send();
    }
    else {
        dispatch_async(self.queue, ^{
            send();
        });
    }
}

-(void)receiveData:(NSData *)data{
    dispatch_async(self.queue, ^{
        [self input_receiveData:data];
    });
}

#pragma mark └ Delegate
-(void)setDelegate:(id<ROUSessionDelegate>)delegate{
    [self setDelegate:delegate queue:nil];
}

-(void)setDelegate:(id<ROUSessionDelegate>)delegate queue:(dispatch_queue_t)queue{
    dispatch_async(self.queue, ^{
        dispatch_queue_t delegateQueue = queue;
        if (nil == queue) {
            delegateQueue = dispatch_get_main_queue();
        }
        rou_dispatch_retain(delegateQueue);
        if (nil != _delegateQueue) {
            rou_dispatch_release(_delegateQueue);
        }
        _delegateQueue = delegateQueue;
        _delegate = delegate;
    });
}

-(void)sendChunkToTransport:(ROUChunk *)chunk {
    [self sendChunkToTransport:chunk immediately:NO];
}

-(void)sendChunkToTransport:(ROUChunk *)chunk immediately:(BOOL)immediately {
    if (self.delegate) {
        
        if (immediately) {
            [self.delegate session:self preparedDataForSending:chunk.encodedChunk];
        }
        else {
            dispatch_async(self.delegateQueue, ^{
                [self.delegate session:self preparedDataForSending:chunk.encodedChunk];
            });
        }
    }
}

-(void)informDelegateOnReceivedChunk:(ROUDataChunk *)chunk{
    if (self.delegate) {
        dispatch_async(self.delegateQueue, ^{
            [self.delegate session:self receivedData:chunk.data];
        });
    }
}

#pragma mark Sending
-(void)input_sendData:(NSData *)data from:(NSString*)sender to:(NSArray<NSString*>*)recipients reliably:(BOOL)reliable immediately:(BOOL)immediately {

    ROUSndDataChunk *chunk = [ROUSndDataChunk chunkWithData:data];

    ROUChunkHeader header = chunk.header;

    setSender(&(header), sender, 0);

    for (int i = 0; i < recipients.count; i++) {
        NSString *recipient = recipients[i];
        if (_sendNextTSNpp[recipient] == nil) {
            _sendNextTSNpp[recipient] = @(0);
        }
        
        setRecipient(&header, recipient, [_sendNextTSNpp[recipient] intValue], i);

        if (reliable) {
            //Increment the TSN count for this recipient
            _sendNextTSNpp[recipient] = @([_sendNextTSNpp[recipient] intValue] + 1);
        }
    }
    
    if (reliable) {
        [self addSndDataChunk:chunk forRecipients:recipients];
        chunk.lastSendDate = [NSDate date];
        
    }
    else {
        //Send it unreliably - no attempt will be made to validate on client end.
        header.type = ROUChunkUnreliable;
    }
    
    
    [self sendChunkToTransport:chunk immediately:immediately];

}

-(void)processAckChunk:(ROUAckChunk *)ackChunk{
    
    //Reset the acknowlegement timeout timer
    [self performSelectorOnMainThread:@selector(resetAckTimeoutTimer) withObject:nil waitUntilDone:NO];
    
    //NEXT:  Iterate on all chunks that still need to be sent.
    // If any of the recipients match this recipient, with the given tsn or below, 'mark' that recipient as received.
    // If that chunk has no remaining recipients, remove the chunk.
    NSString *sender = senderForHeader(ackChunk.header);
    NSNumber *tsnNum = [ackChunk tsnForPlayer:sender];
    NSAssert(tsnNum != nil, @"TSN for sender cannot be nil");
    uint32_t tsn = [tsnNum intValue];
    
    [self removeSndDataChunksUpTo:tsn forRecipient:sender];
    [self removeSndDataChunksAtIndexes:ackChunk.segmentsIndexSet forRecipient:sender];
    
    NSMutableSet *chunksToResend = [NSMutableSet set];
    NSDate *nowDate = [NSDate date];
    
    for (NSString *key in _sndDataChunkIndexSet) {
        NSMutableIndexSet *sndDataChunkIndexSet = _sndDataChunkIndexSet[key];
        [sndDataChunkIndexSet enumerateIndexesUsingBlock:^(NSUInteger tsn, BOOL *stop){
            ROUSndDataChunk *sndChunk = self.sndDataChunks[@(tsn)];
            // resend all that haven't been resent, and those older than the reset timeout
            if ( 0 == sndChunk.resendCount || [nowDate timeIntervalSinceDate:sndChunk.lastSendDate] > self.sndResendTimeout) {
                [chunksToResend addObject:sndChunk];
            }
        }];
    }
    
    for (ROUSndDataChunk *chunk in chunksToResend) {
        chunk.resendCount = chunk.resendCount + 1;
        chunk.lastSendDate = [NSDate date];
        // todo: send a group of chunks in one packet?
        [self sendChunkToTransport:chunk];
    }
}

-(void)addSndDataChunk:(ROUSndDataChunk *)chunk forRecipients:(NSArray*)recipients {
    
    //Set this chunk for each recipient.  Each recipient will need to acknowledge receipt.
    for (NSString *recipient in recipients) {
        
        NSMutableDictionary *sndChunks = _sndDataChunks[recipient];
        if (!sndChunks) {
            sndChunks = [NSMutableDictionary dictionaryWithCapacity:50];
            _sndDataChunks[recipient] = sndChunks;
        }
        NSMutableIndexSet *sndChunkIndexSet = _sndDataChunkIndexSet[recipient];
        if (!sndChunkIndexSet) {
            sndChunkIndexSet = [NSMutableIndexSet indexSet];
            _sndDataChunkIndexSet[recipient] = sndChunkIndexSet;
        }
        NSNumber *tsnNum = [chunk tsnForPlayer:recipient];
        NSAssert(tsnNum != nil, @"Player must have a TSN");

        sndChunks[tsnNum] = chunk;
        [sndChunkIndexSet addIndex:[tsnNum intValue]];
        
    }
}

-(void)removeSndDataChunksUpTo:(uint32_t)beforeTSN forRecipient:(NSString*)recipient {
    NSMutableIndexSet *sndDataChunkIndexSet = _sndDataChunkIndexSet[recipient];
    NSMutableDictionary *sndDataChunks = _sndDataChunks[recipient];
    if (sndDataChunkIndexSet.count == 0) {
        return;
    }
    
    NSUInteger firstIndex = sndDataChunkIndexSet.firstIndex;
    if (beforeTSN < firstIndex) return;
    NSRange range = NSMakeRange(firstIndex, beforeTSN - firstIndex + 1);
    [sndDataChunkIndexSet
     enumerateIndexesInRange:range
     options:0
     usingBlock:^(NSUInteger idx, BOOL *stop) {
         [sndDataChunks removeObjectForKey:@(idx)];
     }];
    [sndDataChunkIndexSet removeIndexesInRange:range];
}

-(void)removeSndDataChunksAtIndexes:(NSIndexSet *)indexes forRecipient:(NSString*)recipient {
    NSMutableDictionary *sndDataChunks = _sndDataChunks[recipient];
    NSMutableIndexSet *sndDataChunkIndexSet = _sndDataChunkIndexSet[recipient];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [sndDataChunks removeObjectForKey:@(idx)];
    }];
    [sndDataChunkIndexSet removeIndexes:indexes];
}

#pragma mark Receiving
-(void)input_receiveData:(NSData *)data{
    NSUInteger packetLength = data.length;
    NSUInteger currentPosition = 0;
    while (currentPosition + ROU_HEADER_SIZE <= packetLength) {
        ROUChunkHeader header;
        [data getBytes:&header range:NSMakeRange(currentPosition, ROU_HEADER_SIZE)];
        if (currentPosition + header.length > packetLength) {
            ROUThrow(@"Incorrect chunk length");
        }
        NSData *encodedChunk =
            [data subdataWithRange:NSMakeRange(currentPosition, header.length)];
        switch (header.type) {
            case ROUChunkTypeData:
                [self processDataChunk:[ROUDataChunk chunkWithEncodedChunk:encodedChunk]];
                break;
            case ROUChunkTypeAck:
                [self processAckChunk:[ROUAckChunk chunkWithEncodedChunk:encodedChunk]];
                break;
            case ROUChunkUnreliable:
                [self informDelegateOnReceivedChunk:[ROUDataChunk chunkWithEncodedChunk:encodedChunk]];
                break;
                
            default:
                break;
        }
        currentPosition += header.length;
    }
}

-(void)processDataChunk:(ROUDataChunk *)chunk{

    //Get the TSN associated with this player
    NSNumber *tsNum = [chunk tsnForPlayer:_localPlayer];
    NSAssert(tsNum != nil, @"This player must exist as a recipient.");

    uint32_t tsn = [tsNum intValue];
    
    if (tsn == _rcvNextTSN) {
        ++_rcvNextTSN;
        [self informDelegateOnReceivedChunk:chunk];
        // check if stored chunks are now ready
        if (self.rcvDataChunkIndexSet.count > 0 &&
            self.rcvDataChunkIndexSet.firstIndex == _rcvNextTSN)
        {
            __block NSRange readyChunksRange;
            [self.rcvDataChunkIndexSet
             enumerateRangesUsingBlock:^(NSRange range, BOOL *stop)
            {
                *stop = YES;
                readyChunksRange = range;
            }];
            _rcvNextTSN += readyChunksRange.length;
            for (NSUInteger tsn = readyChunksRange.location;
                 tsn<_rcvNextTSN;
                 ++tsn)
            {
                ROUDataChunk *chunk = self.rcvDataChunks[@(tsn)];
                [self informDelegateOnReceivedChunk:chunk];
            }
            [self removeRcvDataChunksInRange:readyChunksRange];
        }
    }else if (tsn > _rcvNextTSN){

        [self addRcvDataChunk:chunk tsn:tsn];
        if (self.rcvHasMissedDataChunks) {
            if (!self.rcvMissedPacketsFoundAfterLastPacket) {
                self.rcvAckTimer.fireDate =
                    [NSDate
                     dateWithTimeIntervalSinceNow:ROU_RCV_ACK_TIMER_DELAY_ON_MISSED];
            }
            self.rcvMissedPacketsFoundAfterLastPacket = YES;
        }else{
            if (self.rcvMissedPacketsFoundAfterLastPacket) {
                NSTimeInterval interval = ROU_RCV_ACK_TIMER_INTERVAL;
                if (self.rcvAckTimer.lastFireDate != nil) {
                    interval -= [[NSDate date]
                                 timeIntervalSinceDate:self.rcvAckTimer.lastFireDate];
                    if (interval < 0) interval = 0;
                }
                self.rcvAckTimer.fireDate = [NSDate
                                             dateWithTimeIntervalSinceNow:interval];
            }
            self.rcvMissedPacketsFoundAfterLastPacket = NO;
        }
    }
}

-(void)addRcvDataChunk:(ROUDataChunk *)chunk tsn:(uint32_t)tsn {
    self.rcvDataChunks[@(tsn)] = chunk;
    [self.rcvDataChunkIndexSet addIndex:tsn];
}

-(void)removeRcvDataChunksInRange:(NSRange)range{
    for (NSUInteger tsn = range.location; tsn < range.location + range.length; ++tsn){
        [self.rcvDataChunks removeObjectForKey:@(tsn)];
    }
    [self.rcvDataChunkIndexSet removeIndexesInRange:range];
}

-(BOOL)rcvHasMissedDataChunks{
    NSUInteger count = self.rcvDataChunkIndexSet.count;
    if (0 == count) {
        return NO;
    }
    if (self.rcvDataChunkIndexSet.lastIndex - self.rcvDataChunkIndexSet.firstIndex
        == count - 1)
    {
        return NO;
    }
    return YES;
}

-(void)sendAck{
    
    //ACK chunks only use the primary TSN, which is relative to the recipient's TSN (not the sender's global TSN, they have to look that up)
    ROUAckChunk *chunk = [ROUAckChunk chunk];

    ROUChunkHeader header = chunk.header;
    
    //Set the TSN for this player, so the receiver can easily verify who it's from.  Ignore TSN on the sender.
    setSender(&(header), _localPlayer, _rcvNextTSN-1);
    setRecipient(&(header), _sender, 0, 0);
    
    [self.rcvDataChunkIndexSet
     enumerateRangesInRange:
        NSMakeRange(_rcvNextTSN,
                    self.rcvDataChunkIndexSet.lastIndex-_rcvNextTSN+1)
     options:0
     usingBlock:^(NSRange range, BOOL *stop) {
         [chunk addSegmentWithRange:range];
     }];
    [self sendChunkToTransport:chunk];
}

#pragma mark └ Ack timer
-(void)scheduleAckTimer{
    if (nil != self.rcvAckTimer) {
        return;
    }
    self.rcvAckTimer = [ROUSerialQueueTimer
                        scheduledTimerWithQueue:self.queue
                        target:self
                        selector:@selector(ackTimerFired:)
                        timeInterval:self.rcvAckTimerInterval
                        leeway:self.rcvAckTimerInterval*0.005];
    [self.rcvAckTimer fire];
}

-(void)ackTimerFired:(ROUSerialQueueTimer *)timer{
    [self sendAck];
}

-(void)invalidateAckTimeoutTimer {
    
    if (_ackTimeoutTimer) {
        [_ackTimeoutTimer invalidate];
        self.ackTimeoutTimer = nil;
    }
    
}

-(void)resetAckTimeoutTimer {
    [self invalidateAckTimeoutTimer];
    
    self.ackTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:_rcvAckTimerTimeout target:self selector:@selector(invalidateConnection) userInfo:nil repeats:NO];
    
}

-(void)invalidateConnection {
    if (_delegate) {
        [_delegate invalidConnectionDetectedForSession:self];
    }
    
}

-(void)removePlayer:(NSString*)player {
    
    //Remove entries for this player in objects tracking their data packets
    [_sndDataChunkIndexSet removeObjectForKey:player];
    [_sndDataChunks removeObjectForKey:player];
    [_sendNextTSNpp removeObjectForKey:player];

}

-(void)end {
    [self invalidateAckTimeoutTimer];
}

@end
