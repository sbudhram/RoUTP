//
//  ROUSessionManager.m
//  GKTester
//
//  Created by Shaun Budhram on 1/12/17.
//  Copyright © 2017 Shaun Budhram. All rights reserved.
//

#import "ROUSessionManager.h"
#import "ROUSession.h"

@interface ROUSessionManager () <ROUSessionDelegate>
@end



@implementation ROUSessionManager {
    NSMutableDictionary *_rouRecipients;
    ROUSession *_rouSender;
}

////////////////////////////////////////////////////////////
//
//  Shared Instance Setup
static ROUSessionManager *sharedROUManager = NULL;

+(void) initialize {
    
    @synchronized(self) {
        if (sharedROUManager == NULL)
            sharedROUManager = [[self alloc] init];
    }
    
}

+ (ROUSessionManager*)sharedManager {
    
    return(sharedROUManager);

}

- (void)resetWithLocalPlayerID:(NSString*)localPlayerID {
    
    [_rouRecipients removeAllObjects];
    _rouRecipients = [NSMutableDictionary dictionaryWithCapacity:3];
    _rouSender = nil;
    self.localPlayerID = localPlayerID;
    
    //This object is used to send out all data to recipients, process acknowledgement receipts, and re-send data as needed
    ROUSession *session = [[ROUSession alloc] initWithLocalPlayer:_localPlayerID sender:nil];
    [session setDelegate:self];
    _rouSender = session;
    
}

- (void)addRecipient:(NSString*)recipient {
    //These objects are used exclusively to receive data and send back the corresponding acknowledgement receipts
    ROUSession *session = [[ROUSession alloc] initWithLocalPlayer:_localPlayerID sender:recipient];
    [session setDelegate:self];
    _rouRecipients[recipient] = session;
}

- (void)removeRecipient:(NSString*)recipient {
    [_rouSender removePlayer:recipient];
    [_rouRecipients removeObjectForKey:recipient];
}

- (void)sendData:(NSData *)data toRecipients:(NSArray<NSString*>*)recipients reliably:(BOOL)reliable immediately:(BOOL)immediately {
    [_rouSender sendData:data from:_localPlayerID to:recipients reliably:reliable immediately:immediately];
}

- (void)didReceiveData:(NSData *)data {

    //Parse this data to determine whether it's first-class data, or an acknowledgement receipt.
    //Data is sent to the individual receiver instances, while acknowledgments are redirected to the original sender.
    ROUChunkHeader header = [ROUSession headerForIncomingData:data];
    switch (header.type) {
        case ROUChunkTypeData:
        case ROUChunkUnreliable:
        {
            NSString *recipient = senderForHeader(header);
            [_rouRecipients[recipient] receiveData:data];
            break;
        }
        case ROUChunkTypeAck:
            [_rouSender receiveData:data];
            break;
            
        default:
            break;
    }
}

#pragma mark ROUSessionDelegate callbacks
-(void)session:(ROUSession *)session receivedData:(NSData *)data {
    [_delegate manager:self receivedData:data fromRecipient:session.sender];
}

-(void)session:(ROUSession *)session preparedDataForSending:(NSData *)data {
    [_delegate manager:self preparedDataForSending:data];
}

-(void)invalidConnectionDetectedForSession:(ROUSession *)session {
    [_delegate invalidConnectionDetectedForPlayer:session.sender];
}


@end
