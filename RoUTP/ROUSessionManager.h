//
//  ROUSessionManager.h
//  GKTester
//
//  Created by Shaun Budhram on 1/12/17.
//  Copyright © 2017 Shaun Budhram. All rights reserved.
//

#import <Foundation/Foundation.h>

@class ROUSessionManager;

@protocol ROUSessionManagerDelegate <NSObject>

//Use to process the final data received from the sender, after ROUSessionManager has processed it.
-(void)manager:(ROUSessionManager *)manager receivedData:(NSData *)data fromRecipient:(NSString*)recipient;

//Use to actually send your data out, after ROUSessionManager has prepared it for sending.
-(void)manager:(ROUSessionManager *)manager preparedDataForSending:(NSData *)data;

//If we don't receive an acknowledgment of data received from this player for a set period of time, this will fire.
-(void)invalidConnectionDetectedForPlayer:(NSString*)player;

@end

@interface ROUSessionManager : NSObject

@property (nonatomic, weak) id<ROUSessionManagerDelegate> delegate;
@property (nonatomic, copy) NSString *localPlayerID;

+ (ROUSessionManager*)sharedManager;

//Reset to the initial state.  You must set the sender and recipients after calling this.
- (void)resetWithLocalPlayerID:(NSString*)localPlayerID;

//Add the sender (the local player)
- (void)addSender:(NSString*)sender;

//Add the recipient(s) (up to 3)
- (void)addRecipient:(NSString*)recipient;
- (void)removeRecipient:(NSString*)recipient;

//Send data - call to send your data
- (void)sendData:(NSData *)data toRecipients:(NSArray<NSString*>*)recipients reliably:(BOOL)reliable immediately:(BOOL)immediately;

//Receive data - call when you have received data that needs to be processed by the ROUSessionManager.
- (void)didReceiveData:(NSData *)data;

@end
