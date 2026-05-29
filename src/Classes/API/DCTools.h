//
//  DCWebImageOperations.h
//  Discord Classic
//
//  Created by bag.xml on 3/17/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <objc/NSObjCRuntime.h>
#import <Foundation/Foundation.h>
#import <MediaPlayer/MediaPlayer.h>

@class DCMessage;
@class DCGuild;
@class DCUser;
@class DCEmoji;

#ifdef DEBUG
#define DBGLOG(...) NSLog(__VA_ARGS__)
#else
#define DBGLOG(...) do { } while (0)
#endif

#define TICK(var)   NSDate *tick_##var = [NSDate date]
#define TOCK(var)   NSTimeInterval tick_end_##var = -[tick_##var timeIntervalSinceNow] * 1000.0; if (tick_end_##var > 16.6666666667) NSLog(@"%s @ %s: Time: %f ms (%f frames)", __PRETTY_FUNCTION__, #var, tick_end_##var, tick_end_##var / 16.6666666667)

#define VERSION_MIN(v)                                                  \
    ([[[UIDevice currentDevice] systemVersion] compare:v                \
                                               options:NSNumericSearch] \
     != NSOrderedAscending)
#define appVersion                          \
    [[[NSBundle mainBundle] infoDictionary] \
        objectForKey:@"CFBundleShortVersionString"]

typedef NS_ENUM(uint64_t, DCPermission) {
    DCPermissionCreateInstantInvite = (uint64_t)1 << 0,
    DCPermissionKickMembers = (uint64_t)1 << 1,
    DCPermissionBanMembers = (uint64_t)1 << 2,
    DCPermissionAdministrator = (uint64_t)1 << 3,
    DCPermissionManageChannels = (uint64_t)1 << 4,
    DCPermissionManageGuild = (uint64_t)1 << 5,
    DCPermissionAddReactions = (uint64_t)1 << 6,
    DCPermissionViewAuditLog = (uint64_t)1 << 7,
    DCPermissionPrioritySpeaker = (uint64_t)1 << 8,
    DCPermissionStream = (uint64_t)1 << 9,
    DCPermissionViewChannel = (uint64_t)1 << 10,
    DCPermissionSendMessages = (uint64_t)1 << 11,
    DCPermissionSendTtsMessages = (uint64_t)1 << 12,
    DCPermissionManageMessages = (uint64_t)1 << 13,
    DCPermissionEmbedLinks = (uint64_t)1 << 14,
    DCPermissionAttachFiles = (uint64_t)1 << 15,
    DCPermissionReadMessageHistory = (uint64_t)1 << 16,
    DCPermissionMentionEveryone = (uint64_t)1 << 17,
    DCPermissionUseExternalEmojis = (uint64_t)1 << 18,
    DCPermissionViewGuildInsights = (uint64_t)1 << 19,
    DCPermissionConnect = (uint64_t)1 << 20,
    DCPermissionSpeak = (uint64_t)1 << 21,
    DCPermissionMuteMembers = (uint64_t)1 << 22,
    DCPermissionDeafenMembers = (uint64_t)1 << 23,
    DCPermissionMoveMembers = (uint64_t)1 << 24,
    DCPermissionUseVad = (uint64_t)1 << 25,
    DCPermissionChangeNickname = (uint64_t)1 << 26,
    DCPermissionManageNicknames = (uint64_t)1 << 27,
    DCPermissionManageRoles = (uint64_t)1 << 28,
    DCPermissionManageWebhooks = (uint64_t)1 << 29,
    DCPermissionManageGuildExpressions = (uint64_t)1 << 30,
    DCPermissionUseApplicationCommands = (uint64_t)1 << 31,
    DCPermissionRequestToSpeak = (uint64_t)1 << 32,
    DCPermissionManageEvents = (uint64_t)1 << 33,
    DCPermissionManageThreads = (uint64_t)1 << 34,
    DCPermissionCreatePublicThreads = (uint64_t)1 << 35,
    DCPermissionCreatePrivateThreads = (uint64_t)1 << 36,
    DCPermissionUseExternalStickers = (uint64_t)1 << 37,
    DCPermissionSendMessagesInThreads = (uint64_t)1 << 38,
    DCPermissionUseEmbeddedActivities = (uint64_t)1 << 39,
    DCPermissionModerateMembers = (uint64_t)1 << 40,
    DCPermissionViewCreatorMonetizationAnalytics = (uint64_t)1 << 41,
    DCPermissionUseSoundboard = (uint64_t)1 << 42,
    DCPermissionCreateGuildExpressions = (uint64_t)1 << 43,
    DCPermissionCreateEvents = (uint64_t)1 << 44,
    DCPermissionUseExternalSounds = (uint64_t)1 << 45,
    DCPermissionSendVoiceMessages = (uint64_t)1 << 46,
    // 47, 48
    DCPermissionSendPolls = (uint64_t)1 << 49,
    DCPermissionUseExternalApps = (uint64_t)1 << 50
};

typedef NSString DCSnowflake;

@interface DCTools : NSObject
@property (assign, nonatomic) BOOL oldMode;

// UNTIL RELEASE ONLY
+ (void)checkForAppUpdate;

+ (NSDictionary *)parseJSON:(NSString *)json;
+ (void)alert:(NSString *)title withMessage:(NSString *)message;
+ (NSData *)checkData:(NSData *)response withError:(NSError *)error;

+ (DCMessage *)convertJsonMessage:(NSDictionary *)jsonMessage;
+ (DCGuild *)convertJsonGuild:(NSDictionary *)jsonGuild withMembers:(NSArray *)members;
+ (DCUser *)convertJsonUser:(NSDictionary *)jsonUser cache:(BOOL)cache;
+ (DCEmoji *)convertJsonEmoji:(NSDictionary *)jsonEmoji cache:(BOOL)cache;
+ (NSString *)parseMessage:(NSString *)messageString withGuild:(DCGuild *)guild;
+ (void)getUserAvatar:(DCUser *)user;

+ (void)joinGuild:(NSString *)inviteCode;
@end
