//
//  DCServerCommunicator.h
//  Discord Classic
//
//  Created by Julian Triveri on 3/4/18.
//  Copyright (c) 2018 Julian Triveri. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WSWebSocket.h"
#import "DCGuildListViewController.h"
#import "DCChannelListViewController.h"
#import "DCChatViewController.h"

@interface DCServerCommunicator : NSObject

@property WSWebSocket* websocket;
@property NSString* token;
@property NSString* gatewayURL;
@property NSMutableDictionary* userChannelSettings;

@property NSString* snowflake;

@property NSMutableArray* guilds;
@property NSMutableDictionary* channels;
@property NSMutableDictionary* loadedUsers;

@property DCGuild* selectedGuild;
@property DCChannel* selectedChannel;

@property bool didAuthenticate;

+ (DCServerCommunicator *)sharedInstance;
- (void)startCommunicator;
- (void)sendResume;
- (void)reconnect;
- (void)sendHeartbeat:(NSTimer *)timer;
- (void)sendJSON:(NSDictionary*)dictionary;
@end
