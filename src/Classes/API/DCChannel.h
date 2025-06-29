//
//  DCChannel.h
//  Discord Classic
//
//  Created by bag.xml on 3/12/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

/*DCChannel is a representation of a Discord API Channel object.
 Its easier to work with than raw JSON data and has some handy
 built in functions*/

#import <Foundation/Foundation.h>
#import "DCGuild.h"
#import "DCMessage.h"

@interface DCChannel : NSObject<NSURLConnectionDelegate>
@property NSString* snowflake;
// parent category (for channels) or id of text channel (for threads)
@property NSString* parentID; 
@property NSString* name;
@property NSString* lastMessageId;
@property NSString* lastReadMessageId;
// Icon for a DM
@property UIImage* icon; 
@property bool unread;
@property bool muted;
@property int type;
@property int position;
@property NSMutableDictionary* recipients;
@property DCGuild* parentGuild;
@property NSArray* users;

- (void)checkIfRead;
- (void)sendTypingIndicator;
- (void)sendMessage:(NSString*)message;
- (void)ackMessage:(NSString*)message;
- (void)sendImage:(UIImage*)image mimeType:(NSString*)type;
- (void)sendData:(NSData*)data mimeType:(NSString*)type;
- (void)sendVideo:(NSURL*)videoURL mimeType:(NSString*)type;
- (NSArray*)getMessages:(int)numberOfMessages beforeMessage:(DCMessage*)message;
@end
