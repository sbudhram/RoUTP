//
//  ROUSession.h
//  RoUTPTests
//
//  Created by Yan Rabovik on 27.06.13.
//  Copyright (c) 2013 Yan Rabovik. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ROUDataTypes.h"

#define PLAYER              @"G:277536228"
//#define ROULog(PLAYER, A, X, ...)    ([A isEqual:PLAYER] ? NSLog(X, ##__VA_ARGS__) : sleep(0) )


@class ROUSession;

@protocol ROUSessionDelegate <NSObject>
-(void)session:(ROUSession *)session receivedData:(NSData *)data;
-(void)session:(ROUSession *)session preparedDataForSending:(NSData *)data;
-(void)invalidConnectionDetectedForSession:(ROUSession *)session;
@end

@interface ROUSession : NSObject
/**
 @discussion Session automatically starts on first data sent. Use this method to start
 session earlier.
 */
//Initialize with the local player, and the sender (who is sending to us for this specific session?)
+(ROUChunkHeader)headerForIncomingData:(NSData*)data;
-(id)initWithLocalPlayer:(NSString*)localPlayer sender:(NSString*)sender;
-(void)start;
-(void)sendData:(NSData *)data from:(NSString*)sender to:(NSArray<NSString*>*)recipients reliably:(BOOL)reliable immediately:(BOOL)immediately;
-(void)receiveData:(NSData *)data;
-(void)removePlayer:(NSString*)player;
-(void)setDelegate:(id<ROUSessionDelegate>)delegate;
-(void)end;
@property (nonatomic) NSString *localPlayer;
@property (nonatomic) NSString *sender;
/**
 @queue The queue where the delegate methods will be dispatched.
 The queue is retained by session.
 If no queue specified then dispatch_get_main_queue() will be used.
 */
-(void)setDelegate:(id<ROUSessionDelegate>)delegate
             queue:(dispatch_queue_t)queue;
@end
