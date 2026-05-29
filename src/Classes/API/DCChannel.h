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

#import "DCTools.h"
#import <Foundation/Foundation.h>
#import "DCGuild.h"
#import "DCMessage.h"

typedef NS_ENUM(NSInteger, DCChannelType) {
    DCChannelTypeGuildText          = 0,  // A text channel within a server
    DCChannelTypeDM                 = 1,  // A direct message between users
    DCChannelTypeGuildVoice         = 2,  // A voice channel within a server
    DCChannelTypeGroupDM            = 3,  // A direct message between multiple users
    DCChannelTypeGuildCategory      = 4,  // An organizational category that contains up to 50 channels
    DCChannelTypeGuildAnnouncement  = 5,  // A channel that users can follow and crosspost into their own server (formerly news channels)
    DCChannelTypeAnnouncementThread = 10, // A temporary sub-channel within a GUILD_ANNOUNCEMENT channel
    DCChannelTypePublicThread       = 11, // A temporary sub-channel within a GUILD_TEXT or GUILD_FORUM channel
    DCChannelTypePrivateThread      = 12, // A temporary sub-channel within a GUILD_TEXT channel that is only viewable by those invited and those with the MANAGE_THREADS permission
    DCChannelTypeGuildStageVoice    = 13, // A voice channel for hosting events with an audience
    DCChannelTypeGuildDirectory     = 14, // The channel in a hub containing the listed servers
    DCChannelTypeGuildForum         = 15, // Channel that can only contain threads
    DCChannelTypeGuildMedia         = 16, // Channel that can only contain threads, similar to GUILD_FORUM channels
};

@interface DCChannel : NSObject<NSURLConnectionDelegate>
@property (strong, nonatomic) DCSnowflake* snowflake;
// parent category (for channels) or id of text channel (for threads)
@property (strong, nonatomic) DCSnowflake* parentID;
@property (strong, nonatomic) NSString* name;
@property (strong, nonatomic) DCSnowflake* lastMessageId;
@property (strong, nonatomic) DCSnowflake* lastReadMessageId;
// Icon for a DM
@property (strong, nonatomic) UIImage* icon;
@property (assign, nonatomic) BOOL unread;
@property (assign, nonatomic) BOOL muted;
@property (assign, nonatomic) BOOL writeable;
@property (assign, nonatomic) enum DCChannelType type;
@property (assign, nonatomic) NSInteger position;
// Holds NSDictionary* of Users
@property (strong, nonatomic) NSMutableArray* recipients;
@property (weak, nonatomic) DCGuild* parentGuild;
// Holds NSDictionary* of Users
@property (strong, nonatomic) NSArray* users;

- (void)checkIfRead;
- (void)sendTypingIndicator;
- (void)sendMessage:(NSString*)message referencingMessage:(DCMessage*)referencedMessage disablePing:(BOOL)disablePing;
- (void)editMessage:(DCMessage*)message withContent:(NSString*)content;
- (void)ackMessage:(NSString*)message;
- (void)sendImage:(UIImage*)image mimeType:(NSString*)type;
- (void)sendData:(NSData*)data mimeType:(NSString*)type;
- (void)sendVideo:(NSURL*)videoURL mimeType:(NSString*)type;
- (NSArray*)getMessages:(int)numberOfMessages beforeMessage:(DCMessage*)message;
@end
