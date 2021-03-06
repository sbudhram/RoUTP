//
//  ROUSession_Private.h
//  RoUTPTests
//
//  Created by Yan Rabovik on 27.06.13.
//  Copyright (c) 2013 Yan Rabovik. All rights reserved.
//

#import "ROUSession.h"
#import "ROUDataTypes.h"
#import "ROUSerialQueueTimer.h"

#define ROU_RCV_ACK_TIMER_TIMEOUT 30.0f
#define ROU_RCV_ACK_TIMER_INTERVAL 5.0f
#define ROU_SND_RESEND_TIMEOUT (ROU_RCV_ACK_TIMER_INTERVAL/2.)
#define ROU_RCV_ACK_TIMER_DELAY_ON_MISSED 0.3f

@interface ROUSession ()
-(void)input_sendData:(NSData *)data from:(NSString*)sender to:(NSArray<NSString*>*)recipients reliably:(BOOL)reliable immediately:(BOOL)immediately;
-(void)input_receiveData:(NSData *)data;
-(void)sendChunkToTransport:(ROUChunk *)chunk;
-(void)informDelegateOnReceivedChunk:(ROUDataChunk *)chunk;
-(void)sendAck;
@property (nonatomic) uint32_t rcvNextTSN;

@property (nonatomic) NSMutableDictionary *sendNextTSNpp; //Keys are recipient playerIDs

/**
 @discussion A dictionary of NSData chunks. Keys are NSNumbers holding tsn.
 */
@property (nonatomic,strong) NSMutableDictionary *rcvDataChunks;
@property (nonatomic,strong) NSMutableIndexSet *rcvDataChunkIndexSet;
@property (nonatomic,readonly) BOOL rcvHasMissedDataChunks;
/**
 @discussion A dictionary of ROUSndDataChunk objects. Dual-layered - first layer is recipient ID, 2nd layer is Keys are NSNumbers holding tsn.
 */
@property (nonatomic,strong)NSMutableDictionary *sndDataChunks;
@property (nonatomic,strong) NSMutableDictionary *sndDataChunkIndexSet;
@property (nonatomic,rou_dispatch_property_qualifier) dispatch_queue_t queue;
@property (nonatomic,weak) id<ROUSessionDelegate> delegate;
@property (nonatomic,rou_dispatch_property_qualifier) dispatch_queue_t delegateQueue;
@property (nonatomic) NSTimeInterval rcvAckTimerTimeout;
@property (nonatomic) NSTimeInterval rcvAckTimerInterval;
@property (nonatomic) NSTimeInterval rcvAckTimerDelayOnMissed;
@property (nonatomic) NSTimeInterval sndResendTimeout;
@property (nonatomic,strong) ROUSerialQueueTimer *rcvAckTimer;
@property (nonatomic) BOOL rcvMissedPacketsFoundAfterLastPacket;
@property (nonatomic,strong) NSTimer *ackTimeoutTimer;
@end
