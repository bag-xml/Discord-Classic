//
//  DCWebImageOperations.h
//  Discord Classic
//
//  Created by bag.xml on 3/17/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import "DCGuild.h"
#import "DCMessage.h"
#import "DCUser.h"
#import "DCChatViewController.h"

#define TICK   NSDate *startTime = [NSDate date]
#define TOCK   NSLog(@"%s: Time: %f", __PRETTY_FUNCTION__, -[startTime timeIntervalSinceNow])

#define VERSION_MIN(v)                                                  \
    ([[[UIDevice currentDevice] systemVersion] compare:v                \
                                               options:NSNumericSearch] \
     != NSOrderedAscending)
#define appVersion                          \
    [[[NSBundle mainBundle] infoDictionary] \
        objectForKey:@"CFBundleShortVersionString"]

#define CREATE_INSTANT_INVITE (uint64_t)1 << 0
#define KICK_MEMBERS (uint64_t)1 << 1
#define BAN_MEMBERS (uint64_t)1 << 2
#define ADMINISTRATOR (uint64_t)1 << 3
#define MANAGE_CHANNELS (uint64_t)1 << 4
#define MANAGE_GUILD (uint64_t)1 << 5
#define ADD_REACTIONS (uint64_t)1 << 6
#define VIEW_AUDIT_LOG (uint64_t)1 << 7
#define PRIORITY_SPEAKER (uint64_t)1 << 8
#define STREAM (uint64_t)1 << 9
#define VIEW_CHANNEL (uint64_t)1 << 10
#define SEND_MESSAGES (uint64_t)1 << 11
#define SEND_TTS_MESSAGES (uint64_t)1 << 12
#define MANAGE_MESSAGES (uint64_t)1 << 13
#define EMBED_LINKS (uint64_t)1 << 14
#define ATTACH_FILES (uint64_t)1 << 15
#define READ_MESSAGE_HISTORY (uint64_t)1 << 16
#define MENTION_EVERYONE (uint64_t)1 << 17
#define USE_EXTERNAL_EMOJIS (uint64_t)1 << 18
#define VIEW_GUILD_INSIGHTS (uint64_t)1 << 19
#define CONNECT (uint64_t)1 << 20
#define SPEAK (uint64_t)1 << 21
#define MUTE_MEMBERS (uint64_t)1 << 22
#define DEAFEN_MEMBERS (uint64_t)1 << 23
#define MOVE_MEMBERS (uint64_t)1 << 24
#define USE_VAD (uint64_t)1 << 25
#define CHANGE_NICKNAME (uint64_t)1 << 26
#define MANAGE_NICKNAMES (uint64_t)1 << 27
#define MANAGE_ROLES (uint64_t)1 << 28
#define MANAGE_WEBHOOKS (uint64_t)1 << 29
#define MANAGE_GUILD_EXPRESSIONS (uint64_t)1 << 30
#define USE_APPLICATION_COMMANDS (uint64_t)1 << 31
#define REQUEST_TO_SPEAK (uint64_t)1 << 32
#define MANAGE_EVENTS (uint64_t)1 << 33
#define MANAGE_THREADS (uint64_t)1 << 34
#define CREATE_PUBLIC_THREADS (uint64_t)1 << 35
#define CREATE_PRIVATE_THREADS (uint64_t)1 << 36
#define USE_EXTERNAL_STICKERS (uint64_t)1 << 37
#define SEND_MESSAGES_IN_THREADS (uint64_t)1 << 38
#define USE_EMBEDDED_ACTIVITIES (uint64_t)1 << 39
#define MODERATE_MEMBERS (uint64_t)1 << 40
#define VIEW_CREATOR_MONETIZATION_ANALYTICS (uint64_t)1 << 41
#define USE_SOUNDBOARD (uint64_t)1 << 42
#define CREATE_GUILD_EXPRESSIONS (uint64_t)1 << 43
#define CREATE_EVENTS (uint64_t)1 << 44
#define USE_EXTERNAL_SOUNDS (uint64_t)1 << 45
#define SEND_VOICE_MESSAGES (uint64_t)1 << 46
// 47, 48
#define SEND_POLLS (uint64_t)1 << 49
#define USE_EXTERNAL_APPS (uint64_t)1 << 50


@interface DCTools : NSObject
@property bool oldMode;

+ (void)processImageDataWithURLString:(NSString *)urlString
                             andBlock:(void (^)(UIImage *imageData)
                                      )processImage;


// UNTIL RELEASE ONLY
+ (void)checkForAppUpdate;

+ (NSDictionary *)parseJSON:(NSString *)json;
+ (void)alert:(NSString *)title withMessage:(NSString *)message;
+ (NSData *)checkData:(NSData *)response withError:(NSError *)error;

+ (DCMessage *)convertJsonMessage:(NSDictionary *)jsonMessage;
+ (DCGuild *)convertJsonGuild:(NSDictionary *)jsonGuild;
+ (DCUser *)convertJsonUser:(NSDictionary *)jsonUser cache:(bool)cache;

+ (void)joinGuild:(NSString *)inviteCode;
@end
