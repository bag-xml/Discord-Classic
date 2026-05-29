//
//  DCServerCommunicator.m
//  Discord Classic
//
//  Created by bag.xml on 3/4/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#include "DCServerCommunicator.h"
#include <malloc/malloc.h>
#include <objc/NSObjCRuntime.h>
#import "DCServerCommunicator+Internal.h"
#include "DCUser.h"

#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>
#include <dispatch/dispatch.h>

#include "DCChannel.h"
#include "DCGuild.h"
#include "DCGuildFolder.h"
#include "DCRole.h"
#include "DCTools.h"
#include "SDWebImageManager.h"

@implementation DCServerCommunicator
UIActivityIndicatorView *spinner;
NSTimer *heartbeatTimer = nil;

+ (DCServerCommunicator *)sharedInstance {
    static DCServerCommunicator *sharedInstance = nil;

    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        DBGLOG(@"[DCServerCommunicator] Creating shared instance");
        sharedInstance = [[self alloc] init];

        // Initialize if a sharedInstance does not yet exist

        sharedInstance.gatewayURL      = @"wss://gateway.discord.gg/?encoding=json&v=9";
        sharedInstance.oldMode         = [[NSUserDefaults standardUserDefaults] boolForKey:@"hackyMode"];
        sharedInstance.dataSaver       = [[NSUserDefaults standardUserDefaults] boolForKey:@"dataSaver"];
        sharedInstance.token           = [[NSUserDefaults standardUserDefaults] stringForKey:@"token"];
        sharedInstance.currentUserInfo = nil;

        if ([sharedInstance.token length] == 0) {
            return;
        }

        if (sharedInstance.oldMode == YES) {
            sharedInstance.alertView = [[UIAlertView alloc] initWithTitle:@"Connecting"
                                                                message:@"\n"
                                                               delegate:self
                                                      cancelButtonTitle:nil
                                                      otherButtonTitles:nil];

            UIActivityIndicatorView *spinner = [UIActivityIndicatorView.alloc initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
            [spinner setCenter:CGPointMake(139.5, 75.5)];

            [sharedInstance.alertView addSubview:spinner];
            [spinner startAnimating];
        } else {
            [sharedInstance showNonIntrusiveNotificationWithTitle:@"Connecting..."];
        }
    });

    return sharedInstance;
}

// this no longer sucks

- (void)showNonIntrusiveNotificationWithTitle:(NSString *)title {
    dispatch_async(dispatch_get_main_queue(), ^{
        CGFloat screenWidth        = UIScreen.mainScreen.bounds.size.width;
        CGFloat minimumPadding     = 0;   // Minimum padding threshold
        CGFloat maxPadding         = 120; // Maximum padding
        CGFloat notificationHeight = 50;

        // Calculate title width for iOS 6 compatibility
        CGSize titleSize   = [title sizeWithFont:[UIFont boldSystemFontOfSize:16]];
        CGFloat titleWidth = titleSize.width;

        // Calculate dynamic padding - decrease padding as title gets longer, up to minimumPadding
        CGFloat dynamicPadding    = MAX(minimumPadding, maxPadding - (titleWidth / screenWidth) * (maxPadding - minimumPadding));
        dynamicPadding            = MAX(40, dynamicPadding);
        CGFloat notificationWidth = screenWidth - (dynamicPadding * 2);
        CGFloat notificationX     = dynamicPadding;
        CGFloat notificationY     = -notificationHeight;

        if (self.notificationView != nil) {
            [self.notificationView removeFromSuperview];
            self.notificationView = nil;
        }

        self.notificationView = [[UIView alloc] initWithFrame:CGRectMake(notificationX, notificationY, notificationWidth, notificationHeight)];

        // Create a container view for masking and rounding
        UIView *maskView             = [[UIView alloc] initWithFrame:self.notificationView.bounds];
        maskView.backgroundColor     = [UIColor colorWithPatternImage:[UIImage imageNamed:@"No-header"]];
        maskView.layer.cornerRadius  = 15;
        maskView.layer.masksToBounds = YES; // Important: Masking the view to fix corner clipping

        [self.notificationView addSubview:maskView];
        [self.notificationView sendSubviewToBack:maskView];

        self.notificationView.layer.shadowColor   = [UIColor blackColor].CGColor;
        self.notificationView.layer.shadowOffset  = CGSizeMake(0, 2);
        self.notificationView.layer.shadowOpacity = 0.6;
        self.notificationView.layer.shadowRadius  = 5;
        self.notificationView.layer.borderColor   = [UIColor darkGrayColor].CGColor;
        self.notificationView.layer.borderWidth   = 1.0;
        self.notificationView.layer.cornerRadius  = 15;

        CGFloat spinnerWidth  = 30;
        CGFloat labelWidth    = notificationWidth - spinnerWidth - 10; // Reduce space between label and spinner
        UILabel *label        = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, labelWidth, notificationHeight)];
        label.text            = title;
        label.backgroundColor = [UIColor clearColor];
        label.textColor       = [UIColor colorWithRed:168 / 255.0 green:168 / 255.0 blue:168 / 255.0 alpha:1];
        label.font            = [UIFont boldSystemFontOfSize:16];
        label.textAlignment   = (NSTextAlignment)UITextAlignmentLeft;
        label.lineBreakMode   = NSLineBreakByTruncatingTail;
        label.shadowColor     = [UIColor colorWithRed:0 / 255.0 green:0 / 255.0 blue:0 / 255.0 alpha:1];
        label.shadowOffset    = CGSizeMake(0, 1);

        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        spinner.center                   = CGPointMake(notificationWidth - (spinnerWidth / 2) - 5, notificationHeight / 2); // Adjust spinner closer to text
        [spinner startAnimating];

        [self.notificationView addSubview:label];
        [self.notificationView addSubview:spinner];

        UIWindow *window = [[[UIApplication sharedApplication] windows] lastObject];
        [window addSubview:self.notificationView];

        [UIView animateWithDuration:0.6
                         animations:^{
                             self.notificationView.frame = CGRectMake(notificationX, 64, notificationWidth, notificationHeight);
                         }];
    });
}

- (void)dismissNotification {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Animate out
        [UIView animateWithDuration:0.4
            animations:^{
                CGRect frame                = self.notificationView.frame;
                frame.origin.y              = -frame.size.height; // Move off-screen
                self.notificationView.frame = frame;
            }
            completion:^(BOOL finished) {
                [self.notificationView removeFromSuperview];
                self.notificationView = nil;
            }];
    });
}


- (DCChannel *)findChannelById:(NSString *)channelId {
    for (DCGuild *guild in self.guilds) { // Replace `self.guilds` with your guilds array
        for (DCChannel *channel in guild.channels) {
            if ([channel.snowflake isEqualToString:channelId]) {
                return channel;
            }
        }
    }
    return nil;
}

#pragma mark - Discord Event Handlers

- (void)handleReadyWithData:(NSDictionary *)d {
    self.didAuthenticate = true;
    DBGLOG(@"Did authenticate!");
    if (self.oldMode == NO) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showNonIntrusiveNotificationWithTitle:@"Getting Ready..."];
        });
    }
    // Grab session id (used for RESUME) and user id
    self.sessionId = [NSString stringWithFormat:@"%@", [d valueForKeyPath:@"session_id"]];
    // THIS IS US, hey hey hey this is MEEEEE BITCCCH MORTY DID YOU HEAR, THIS IS ME, AND MY USER ID, YES MORT(BUÜÜÜRPP)Y, THIS IS ME. BITCCHHHH. 100 YEARS OF DISCORD CLASSIC MORTYY YOU AND MEEEE
    self.snowflake       = [NSString stringWithFormat:@"%@", [d valueForKeyPath:@"user.id"]];
    DCUserInfo *userInfo = [DCUserInfo new];
    userInfo.username    = [d valueForKeyPath:@"user.username"];
    if ([[d valueForKeyPath:@"user.global_name"] isKindOfClass:[NSNull class]]) {
        userInfo.globalName = [d valueForKeyPath:@"user.username"];
    } else {
        userInfo.globalName = [d valueForKeyPath:@"user.global_name"];
    }
    userInfo.pronouns          = [d valueForKeyPath:@"user.pronouns"];
    userInfo.avatar            = [d valueForKeyPath:@"user.avatar"];
    userInfo.phone             = [d valueForKeyPath:@"user.phone"];
    userInfo.email             = [d valueForKeyPath:@"user.email"];
    userInfo.bio               = [d valueForKeyPath:@"user.bio"];
    userInfo.banner            = [d valueForKeyPath:@"user.banner"];
    userInfo.bannerColor       = [d valueForKeyPath:@"user.banner_color"];
    userInfo.clan              = [d valueForKeyPath:@"user.clan"];
    userInfo.id                = [d valueForKeyPath:@"user.id"];
    userInfo.connectedAccounts = [d valueForKeyPath:@"connected_accounts"];
    self.currentUserInfo       = userInfo;
    self.userChannelSettings   = NSMutableDictionary.new;
    for (NSDictionary *guildSettings in [d objectForKey:@"user_guild_settings"]) {
        for (NSDictionary *channelSetting in [guildSettings objectForKey:@"channel_overrides"]) {
            [self.userChannelSettings setValue:@((bool)[channelSetting objectForKey:@"muted"]) forKey:[channelSetting objectForKey:@"channel_id"]];
        }
    }
    // Get users from READY payload (DEDUPE_USER_OBJECTS)
    [self.loadedUsers setObject:[DCTools convertJsonUser:[d objectForKey:@"user"]
                                                   cache:YES]
                         forKey:[d valueForKeyPath:@"user.id"]];
    for (NSDictionary *user in [d objectForKey:@"users"]) {
        @autoreleasepool {
            DCUser *dcUser = [DCTools convertJsonUser:user cache:YES];
            if (dcUser) {
                [self.loadedUsers setObject:dcUser forKey:dcUser.snowflake];
                // NSLog(@"[READY] Cached user: %@ (ID: %@)", dcUser.username, dcUser.snowflake);
            } else {
                DBGLOG(@"[READY] Failed to convert user: %@", user);
            }
        }
    }

    // Get user DMs and DM groups
    // The user's DMs are treated like a guild, where the channels are different DM/groups
    DCGuild *privateGuild = DCGuild.new;
    privateGuild.name     = @"Direct Messages";
    if (self.oldMode == NO) {
        privateGuild.icon = [UIImage imageNamed:@"privateGuildLogo"];
    }
    privateGuild.channels  = NSMutableArray.new;
    privateGuild.snowflake = nil;
    for (NSDictionary *privateChannel in [d objectForKey:@"private_channels"]) {
        @autoreleasepool {
            // this may actually suck
            // NSLog(@"%@", privateChannel);
            DCChannel *newChannel    = DCChannel.new;
            newChannel.parentID      = [privateChannel objectForKey:@"parent_id"];
            newChannel.snowflake     = [privateChannel objectForKey:@"id"];
            newChannel.lastMessageId = [privateChannel objectForKey:@"last_message_id"];
            newChannel.parentGuild   = privateGuild;
            newChannel.type          = DCChannelTypeDM; // Direct Message channel
            newChannel.writeable     = YES;             // DMs are always writeable
            newChannel.recipients    = NSMutableArray.new;
            { // default icon
                NSNumber *longId = @([newChannel.snowflake longLongValue]);
                int selector     = (int)(([longId longLongValue] >> 22) % 6);
                newChannel.icon  = [[DCUser defaultAvatars] objectAtIndex:selector];
                CGSize itemSize  = CGSizeMake(32, 32);
                UIGraphicsBeginImageContextWithOptions(itemSize, NO, UIScreen.mainScreen.scale);
                CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
                [newChannel.icon drawInRect:imageRect];
                newChannel.icon = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
            }
            NSArray *recipientIds = [privateChannel objectForKey:@"recipient_ids"];
            if (recipientIds && recipientIds.count > 0) {
                for (NSString *userId in recipientIds) {
                    DCUser *recipient = [self.loadedUsers objectForKey:userId];
                    if (!recipient) {
                        DBGLOG(@"[READY] User ID %@ not found in loadedUsers", userId);
                        continue;
                    }
                    [newChannel.recipients addObject:recipient];
                }
                NSMutableArray *mUsers = [newChannel.recipients mutableCopy];
                [mUsers addObject:[self.loadedUsers objectForKey:self.snowflake]];
                newChannel.users = mUsers;
            }
            if ([privateChannel objectForKey:@"icon"] && [privateChannel objectForKey:@"icon"] != [NSNull null]) {
                NSURL *iconURL             = [NSURL URLWithString:[NSString stringWithFormat:@"https://cdn.discordapp.com/channel-icons/%@/%@.png?size=64",
                                                                                 newChannel.snowflake, [privateChannel objectForKey:@"icon"]]];
                SDWebImageManager *manager = [SDWebImageManager sharedManager];
                [manager downloadImageWithURL:iconURL
                                      options:0
                                     progress:nil
                                    completed:^(UIImage *icon, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                        @autoreleasepool {
                                            if (!icon || !finished) {
                                                NSLog(@"Failed to load channel icon with URL %@: %@", iconURL, error);
                                                return;
                                            }
                                            newChannel.icon = icon;
                                            CGSize itemSize = CGSizeMake(32, 32);
                                            dispatch_async(dispatch_get_main_queue(), ^{
                                                UIGraphicsBeginImageContextWithOptions(itemSize, NO, UIScreen.mainScreen.scale);
                                                CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
                                                [newChannel.icon drawInRect:imageRect];
                                                newChannel.icon = UIGraphicsGetImageFromCurrentImageContext();
                                                UIGraphicsEndImageContext();
                                            });
                                        }
                                    }];
            } else {
                if (newChannel.recipients.count > 0) {
                    DCUser *user = [newChannel.recipients objectAtIndex:0];

                    NSURL *avatarURL           = [NSURL URLWithString:[NSString
                                                                stringWithFormat:@"https://cdn.discordapp.com/avatars/%@/%@.png?size=64",
                                                                                 user.snowflake,
                                                                                 user.avatarID]];
                    SDWebImageManager *manager = [SDWebImageManager sharedManager];
                    [manager downloadImageWithURL:avatarURL
                                          options:0
                                         progress:nil
                                        completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                            @autoreleasepool {
                                                if (image && finished) {
                                                    newChannel.icon = image;
                                                    CGSize itemSize = CGSizeMake(32, 32);
                                                    dispatch_async(dispatch_get_main_queue(), ^{
                                                        UIGraphicsBeginImageContextWithOptions(itemSize, NO, UIScreen.mainScreen.scale);
                                                        CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
                                                        [newChannel.icon drawInRect:imageRect];
                                                        newChannel.icon = UIGraphicsGetImageFromCurrentImageContext();
                                                        UIGraphicsEndImageContext();
                                                        [NSNotificationCenter.defaultCenter postNotificationName:@"RELOAD CHANNEL LIST" object:nil];
                                                    });
                                                } else {
                                                    // NSLog(@"Failed to download user avatar with URL %@: %@", avatarURL, error);
                                                    int selector            = 0;
                                                    NSNumber *discriminator = @(user.discriminator);
                                                    if ([discriminator integerValue] == 0) {
                                                        NSNumber *longId = @([user.snowflake longLongValue]);
                                                        selector         = (int)(([longId longLongValue] >> 22) % 6);
                                                    } else {
                                                        selector = (int)([discriminator integerValue] % 5);
                                                    }
                                                    newChannel.icon = [[DCUser defaultAvatars] objectAtIndex:selector];
                                                    CGSize itemSize = CGSizeMake(32, 32);
                                                    dispatch_async(dispatch_get_main_queue(), ^{
                                                        UIGraphicsBeginImageContextWithOptions(itemSize, NO, UIScreen.mainScreen.scale);
                                                        CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
                                                        [newChannel.icon drawInRect:imageRect];
                                                        newChannel.icon = UIGraphicsGetImageFromCurrentImageContext();
                                                        UIGraphicsEndImageContext();
                                                        [NSNotificationCenter.defaultCenter postNotificationName:@"RELOAD CHANNEL LIST" object:nil];
                                                    });
                                                }
                                            }
                                        }];
                }
            }
            NSString *privateChannelName = [privateChannel objectForKey:@"name"];
            // Some private channels dont have names, check if nil
            if (privateChannelName && (NSNull *)privateChannelName != [NSNull null]) {
                newChannel.name = privateChannelName;
            } else {
                // If no name, create a name from channel members
                NSMutableString *fullChannelName = [@"" mutableCopy];
                for (DCUser *recipient in newChannel.recipients) {
                    @autoreleasepool {
                        // add comma between member names
                        if ([newChannel.recipients indexOfObject:recipient] != 0) {
                            [fullChannelName appendString:@", "];
                        }
                        NSString *memberName = recipient.username;
                        if (recipient.globalName && [recipient.globalName isKindOfClass:[NSString class]]) {
                            memberName = recipient.globalName;
                        }
                        if (memberName) {
                            [fullChannelName appendString:memberName];
                        }
                        newChannel.name = fullChannelName;
                    }
                }
            }
            [privateGuild.channels addObject:newChannel];
        }
    }

    // Process user presences from READY payload (DEDUPE_USER_OBJECTS)
    NSDictionary *merged_presences = [d objectForKey:@"merged_presences"];
    NSMutableArray *presences      = NSMutableArray.new;
    for (NSDictionary *presence in merged_presences[@"friends"]) {
        @autoreleasepool {
            [presences addObject:presence];
        }
    }
    for (NSArray *guildPresences in merged_presences[@"guilds"]) {
        @autoreleasepool {
            for (NSDictionary *presence in guildPresences) {
                @autoreleasepool {
                    [presences addObject:presence];
                }
            }
        }
    }
    for (NSDictionary *presence in presences) {
        NSString *userId = [presence objectForKey:@"user_id"];
        NSString *status = [presence objectForKey:@"status"];
        if (!userId || !status) {
            continue;
        }
        DCUser *user = [self.loadedUsers objectForKey:userId];
        if (!user) {
            DBGLOG(@"[READY] User ID %@ not found in loadedUsers", userId);
            continue;
        }
        user.status = [DCUser statusFromString:status];
        // NSLog(@"[READY] User %@ (ID: %@) has status: %@ (%ld)", user.username, userId, status, (long)user.status);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:@"RELOAD CHANNEL LIST" object:nil];
    });

    // Sort the DMs list by most recent...
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor
        sortDescriptorWithKey:@"lastMessageId"
                    ascending:NO
                     selector:@selector(localizedStandardCompare:)];
    [privateGuild.channels sortUsingDescriptors:@[ sortDescriptor ]];
    NSMutableDictionary *channelsDict = NSMutableDictionary.new;
    for (DCChannel *channel in privateGuild.channels) {
        [channelsDict setObject:channel forKey:channel.snowflake];
    }
    self.channels          = channelsDict;
    NSMutableArray *guilds = NSMutableArray.new;
    [guilds addObject:privateGuild];
    // Get servers (guilds) the user is a member of
    NSArray *mergedMembers = [d objectForKey:@"merged_members"];
    NSArray *guildJsons    = [d objectForKey:@"guilds"];
    for (NSUInteger i = 0; i < guildJsons.count; i++) {
        @autoreleasepool {
            DCGuild *guild = [DCTools convertJsonGuild:[guildJsons objectAtIndex:i]
                                           withMembers:[mergedMembers objectAtIndex:i]];
            [guilds addObject:guild];
        }
    }
    userInfo.guildPositions = NSMutableArray.new;
    if ([d valueForKeyPath:@"user_settings.guild_positions"]) {
        [userInfo.guildPositions addObjectsFromArray:[d valueForKeyPath:@"user_settings.guild_positions"]];
    } else if ([d valueForKeyPath:@"user_settings.guild_folders"]) {
        userInfo.guildFolders = NSMutableArray.new;
        for (NSDictionary *userDict in [d valueForKeyPath:@"user_settings.guild_folders"]) {
            @autoreleasepool {
                DCGuildFolder *folder    = [DCGuildFolder new];
                folder.id                = [userDict objectForKey:@"id"] != [NSNull null] ? [[userDict objectForKey:@"id"] intValue] : 0;
                folder.name              = [userDict objectForKey:@"name"];
                folder.color             = [userDict objectForKey:@"color"] != [NSNull null] ? [[userDict objectForKey:@"color"] intValue] : 0;
                NSMutableArray *guildIds = [[userDict objectForKey:@"guild_ids"] mutableCopy];
                // below code required for deleted but not updated guilds
                for (NSUInteger i = guildIds.count - 1; i > 0; i--) {
                    NSString *guildId = [guildIds objectAtIndex:i];
                    if ([guilds indexOfObjectPassingTest:
                                    ^BOOL(DCGuild *guild, NSUInteger idx, BOOL *stop) {
                                        return [guild.snowflake isEqualToString:guildId];
                                    }]
                        == NSNotFound) {
                        DBGLOG(@"[READY] Guild ID %@ not found in guilds array!", guildId);
                        [guildIds removeObjectAtIndex:i];
                    }
                }
                folder.guildIds  = guildIds;
                NSNumber *opened = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:[@(folder.id) stringValue]] objectForKey:@"opened"];
                folder.opened    = opened != nil ? [opened boolValue] : YES; // default to opened
                [userInfo.guildFolders addObject:folder];
                [userInfo.guildPositions addObjectsFromArray:folder.guildIds];
            }
        }
    } else {
        NSLog(@"no guild positions found in user settings");
    }
    for (NSDictionary *guildSettings in [d objectForKey:@"user_guild_settings"]) {
        NSString *guildId = [guildSettings objectForKey:@"guild_id"];
        if ((NSNull *)guildId == [NSNull null]) {
            ((DCGuild *)[guilds objectAtIndex:0]).muted = [[guildSettings objectForKey:@"muted"] boolValue];
            continue;
        }
        for (DCGuild *guild in guilds) {
            if ([guild.snowflake isEqualToString:guildId]) {
                guild.muted = [[guildSettings objectForKey:@"muted"] boolValue];
                break;
            }
        }
    }
    self.guilds         = guilds;
    self.guildsIsSorted = NO;
    // Read states are recieved in READY payload
    // they give a channel ID and the ID of the last read message in that channel
    NSArray *readstatesArray = [d objectForKey:@"read_state"];
    for (NSDictionary *readstate in readstatesArray) {
        NSString *readstateChannelId = [readstate objectForKey:@"id"];
        NSString *readstateMessageId = [readstate objectForKey:@"last_message_id"];
        // Get the channel with the ID of readStateChannelId
        DCChannel *channelOfReadstate        = [self.channels objectForKey:readstateChannelId];
        channelOfReadstate.lastReadMessageId = readstateMessageId;
        [channelOfReadstate checkIfRead];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:@"READY" object:self];
        // Dismiss the 'reconnecting' dialogue box
        [self.alertView dismissWithClickedButtonIndex:0 animated:YES];
        [self dismissNotification];
    });
}

- (void)handlePresenceUpdateEventWithData:(NSDictionary *)d {
    @autoreleasepool {
        NSString *userId = [d valueForKeyPath:@"user.id"];
        NSString *status = [d objectForKey:@"status"];
        if (!userId || !status) {
            // NSLog(@"[PRESENCE_UPDATE] Missing user ID or status in payload: %@", d);
            return;
        }
        DCUser *user = [self.loadedUsers objectForKey:userId];
        if (user) {
            user.status = [DCUser statusFromString:status];
            // NSLog(@"[PRESENCE_UPDATE] Updated user %@ (ID: %@) to status: %ld", user.username, userId, (long)user.status);
        } else {
            // Cache user if not already in loadedUsers
            NSDictionary *userDict = [d objectForKey:@"user"];
            if (userDict) {
                user = [DCTools convertJsonUser:userDict cache:YES];
                [self.loadedUsers setObject:user forKey:userId];
                user.status = [DCUser statusFromString:status];
                // NSLog(@"[PRESENCE_UPDATE] Cached and updated user %@ (ID: %@) to status: %ld", user.username, userId, (long)user.status);
            }
        }
        // IMPORTANT: Post a notification so we can refresh DM status dots
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:@"USER_PRESENCE_UPDATED" object:user];
        });
    }
}

- (void)handleMessageCreateWithData:(NSDictionary *)d {
    @autoreleasepool {
        NSString *channelIdOfMessage = [d objectForKey:@"channel_id"];
        NSString *messageId          = [d objectForKey:@"id"];
        // Check if a channel is currently being viewed
        // and if so, if that channel is the same the message was sent in
        if (self.selectedChannel != nil && [channelIdOfMessage isEqualToString:self.selectedChannel.snowflake]) {
            // NSLog(@"[MESSAGE_CREATE] Message received in currently selected channel: %@", self.selectedChannel.name);
            dispatch_async(dispatch_get_main_queue(), ^{
                // Send notification with the new message
                // will be recieved by DCChatViewController
                [NSNotificationCenter.defaultCenter postNotificationName:@"MESSAGE CREATE" object:self userInfo:d];
            }); // Update current channel & read state last message
            [self.selectedChannel setLastMessageId:messageId];
            // Ack message since we are currently viewing this channel
            [self.selectedChannel ackMessage:messageId];
        } else {
            DCChannel *channelOfMessage = [self.channels objectForKey:channelIdOfMessage];
            // NSLog(@"[MESSAGE_CREATE] Message received in channel %@ (ID: %@) not currently selected", channelOfMessage.name, channelIdOfMessage);
            channelOfMessage.lastMessageId = messageId;
            [channelOfMessage checkIfRead];
            dispatch_async(dispatch_get_main_queue(), ^{
                [NSNotificationCenter.defaultCenter postNotificationName:@"MESSAGE ACK" object:self];
            });
        }
    }
}

- (void)handleMessageUpdateWithData:(NSDictionary *)d {
    NSString *channelIdOfMessage = [d objectForKey:@"channel_id"];
    NSString *messageId          = [d objectForKey:@"id"];
    // Check if a channel is currently being viewed
    // and if so, if that channel is the same the message was sent in
    if (self.selectedChannel != nil && [channelIdOfMessage isEqualToString:self.selectedChannel.snowflake]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Send notification with the new message
            // will be recieved by DCChatViewController
            [NSNotificationCenter.defaultCenter postNotificationName:@"MESSAGE EDIT" object:self userInfo:d];
        });
        // Update current channel & read state last message
        [self.selectedChannel setLastMessageId:messageId];
        // Ack message since we are currently viewing this channel
        [self.selectedChannel ackMessage:messageId];
    }
}

- (void)handleChannelCreateWithData:(NSDictionary *)d {
    DCChannel *newChannel = DCChannel.new;
    newChannel.snowflake  = [d objectForKey:@"id"];
    newChannel.parentID   = [d objectForKey:@"parent_id"];
    newChannel.name       = [d objectForKey:@"name"];
    newChannel.lastMessageId =
        [d objectForKey:@"last_message_id"];
    if ([d objectForKey:@"guild_id"] != nil) {
        for (DCGuild *guild in self.guilds) {
            if ([guild.snowflake isEqualToString:[d objectForKey:@"guild_id"]]) {
                newChannel.parentGuild = guild;
                break;
            }
        }
    }
    newChannel.type       = [[d objectForKey:@"type"] intValue];
    NSString *rawPosition = [d objectForKey:@"position"];
    newChannel.position   = rawPosition ? [rawPosition intValue] : 0;
}

- (id)handleGuildMemberItemWithItem:(NSDictionary *)item {
    if ([item objectForKey:@"group"]) {
        NSDictionary *groupItem = [item objectForKey:@"group"];
        id ret                  = [self.loadedRoles objectForKey:[groupItem objectForKey:@"id"]];
        if (!ret) {
            // fake online/offline roles
            DCRole *role   = DCRole.new;
            role.snowflake = [groupItem objectForKey:@"id"];
            if ([role.snowflake isEqualToString:@"online"]) {
                role.name = @"Online";
            } else if ([role.snowflake isEqualToString:@"offline"]) {
                role.name = @"Offline";
            } else {
                role.name = [groupItem objectForKey:@"id"];
            }
            [self.loadedRoles setObject:role forKey:[groupItem objectForKey:@"id"]];
            ret = role;
        }
        return ret;
    } else if ([item objectForKey:@"member"]) {
        NSDictionary *memberItem = [item objectForKey:@"member"];
        DCUser *user             = [self.loadedUsers objectForKey:[memberItem valueForKeyPath:@"user.id"]];
        if (!user) {
            user = [DCTools convertJsonUser:[memberItem objectForKey:@"user"] cache:YES];
            [self.loadedUsers setObject:user forKey:user.snowflake];
        }
        user.status = [DCUser statusFromString:[memberItem valueForKeyPath:@"presence.status"]];
        return user;
    } else {
        return nil;
    }
}

#define SYNC @"SYNC"
#define UPDATE @"UPDATE"
#define DELETE @"DELETE"
#define INSERT @"INSERT"

- (void)handleGuildMemberListUpdateWithData:(NSDictionary *)d {
    DCGuild *guild = nil;
    for (DCGuild *g in self.guilds) {
        if ([g.snowflake isEqualToString:[d objectForKey:@"guild_id"]]) {
            guild = g;
            break;
        }
    }
    if (!guild) {
        return;
    }
    @synchronized(guild) {
        guild.memberCount = [[d objectForKey:@"member_count"] intValue];
        guild.onlineCount = [[d objectForKey:@"online_count"] intValue];
    }
    @synchronized(guild.members) {
        for (NSDictionary *op in [d objectForKey:@"ops"]) {
            if ([[op objectForKey:@"op"] isEqualToString:SYNC]) {
                if (![[op objectForKey:@"items"] isKindOfClass:[NSArray class]]
                    || [((NSArray *)[op objectForKey:@"items"]) count] == 0) {
                    DBGLOG(@"Guild member list update SYNC op without items: %@", op);
                    continue;
                }
                guild.members = NSMutableArray.new;
                // #ifdef DEBUG
                //              NSLog(
                //                  @"SYNC: length: %lu, range: [%lu..%lu]",
                //                  (unsigned long)[op[@"items"] count],
                //                  (unsigned long)[op[@"range"][0] integerValue],
                //                  (unsigned long)[op[@"range"][1] integerValue]
                //              );
                // #endif
                for (NSDictionary *item in [op objectForKey:@"items"]) {
                    id member = [self handleGuildMemberItemWithItem:item];
                    if (!member) {
                        DBGLOG(@"Guild member list update SYNC op with invalid item: %@", item);
                        continue;
                    }
                    [guild.members addObject:member];
                }
            } else if ([[op objectForKey:@"op"] isEqualToString:UPDATE]) {
                NSDictionary *item = [op objectForKey:@"item"];
                id member          = [self handleGuildMemberItemWithItem:item];
                if (!member) {
                    DBGLOG(@"Guild member list update UPDATE op with invalid item: %@", item);
                    continue;
                }
                NSUInteger index = [[op objectForKey:@"index"] intValue];
                if (index >= [guild.members count]) {
                    index = [guild.members count] - 1;
                } else if (index < 0) {
                    index = 0;
                }
                // #ifdef DEBUG
                //              NSLog(@"Updating %s at index: %lu", [member isKindOfClass:[DCUser class]] ? "user" : "role", (unsigned long)index);
                // #endif
                [guild.members replaceObjectAtIndex:(NSUInteger)index withObject:(id)member];
            } else if ([[op objectForKey:@"op"] isEqualToString:DELETE]) {
                NSUInteger index = [[op objectForKey:@"index"] intValue];
                if (index >= [guild.members count]) {
                    index = [guild.members count] - 1;
                } else if (index < 0) {
                    index = 0;
                }
                // #ifdef DEBUG
                //              NSLog(@"Deleting at index: %lu", (unsigned long)index);
                // #endif
                [guild.members removeObjectAtIndex:index];
            } else if ([[op objectForKey:@"op"] isEqualToString:INSERT]) {
                NSUInteger index = [[op objectForKey:@"index"] intValue];
                if (index > [guild.members count]) {
                    index = [guild.members count] - 1;
                } else if (index < 0) {
                    index = 0;
                }
                NSDictionary *item = [op objectForKey:@"item"];
                id member          = [self handleGuildMemberItemWithItem:item];
                if (!member) {
                    DBGLOG(@"Guild member list update INSERT op with invalid item: %@", item);
                    continue;
                }
                // #ifdef DEBUG
                //              NSLog(@"Inserting %s at index: %lu", [member isKindOfClass:[DCUser class]] ? "user" : "role", (unsigned long)index);
                // #endif
                [guild.members insertObject:member atIndex:index];
            } else {
                DBGLOG(@"Unhandled guild member list update op: %@", op);
            }
        }
        if ([guild.members count] > 100) {
            // NSLog(@"Capping guild members at 100");
            guild.members = [[guild.members subarrayWithRange:NSMakeRange(0, 100)] mutableCopy];
        }
        // #ifdef DEBUG
        //      NSLog(@"size: %lu", (unsigned long)[guild.members count]);
        // #endif
    }
    if (self.selectedChannel != nil && [self.selectedChannel.parentGuild.snowflake isEqualToString:guild.snowflake]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:@"GuildMemberListUpdated" object:nil];
        });
    }
}

#pragma mark - WebSocket Event Handlers

- (void)handleHelloWithData:(NSDictionary *)d {
    int heartbeatInterval = [[d objectForKey:@"heartbeat_interval"] intValue];
    if (!heartbeatTimer) {
        float heartbeatSeconds = (float)heartbeatInterval / 1000;
        float jitterHeartbeat  = heartbeatSeconds * (arc4random_uniform(1000) / 1000.0f);
        self.gotHeartbeat      = false;
        DBGLOG(@"Heartbeat is %f seconds, jitter is %f seconds", heartbeatSeconds, jitterHeartbeat);
        dispatch_async(dispatch_get_main_queue(), ^{
            heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:jitterHeartbeat
                                                              target:self
                                                            selector:@selector(jitterBeat:)
                                                            userInfo:@{@"heartbeatInterval" : @(heartbeatSeconds)}
                                                             repeats:NO];
        });
    };
    if (self.sequenceNumber && self.sessionId) {
        DBGLOG(@"Sending Resume with sequence number %li, session ID %@", (long)self.sequenceNumber, self.sessionId);
        // RESUME
        [self sendJSON:@{
            @"op" : @(DCGatewayOpCodeResume),
            @"d" : @{
                @"token" : self.token,
                @"session_id" : self.sessionId,
                @"seq" : @(self.sequenceNumber),
            }
        }];
    } else {
        DBGLOG(@"Sending Identify");
        [self sendJSON:@{
            @"op" : @(DCGatewayOpCodeIdentify),
            @"d" : @{
                @"token" : self.token,
                @"properties" : @{
                    @"os" : @"iOS",
                    @"browser" : @"Discord iOS",
                    // browser_version
                    // release_channel
                    // system_locale
                    // is_fast_connect
                    // version
                },
                @"large_threshold" : @"50",
                @"capabilities" : @(
                    DCGatewayCapabilitiesDebounceMessageReactions // not handling it anyways
                    | DCGatewayCapabilitiesLazyUserNotes          // not handling it anyways
                    | DCGatewayCapabilitiesDedupeUserObjects      // dedupe user objects in READY payload
                ),
            }
        }];
        // Disable ability to identify until reenabled 5 seconds later.
        // API only allows once identify every 5 seconds
        self.canIdentify = false;
        /* do not initialize guilds and channels here,
           could cause concurrency issues while guilds and channels are being loaded */
        self.loadedUsers                                                  = NSMutableDictionary.new;
        self.loadedRoles                                                  = NSMutableDictionary.new;
        self.loadedEmojis                                                 = NSMutableDictionary.new;
        self.gotHeartbeat                                                 = true;
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        // Reenable ability to identify in 5 seconds
        dispatch_async(dispatch_get_main_queue(), ^{
            self.cooldownTimer = [NSTimer scheduledTimerWithTimeInterval:5
                                                                  target:self
                                                                selector:@selector(refreshcanIdentify:)
                                                                userInfo:nil
                                                                 repeats:NO];
        });
    }
}

- (void)sendGuildSubscriptionWithGuildId:(NSString *)guildId channelId:(NSString *)channelId {
    if (!self.token || !self.sessionId) {
        return;
    } else if (!guildId || !channelId) {
        return;
    }
    // #ifdef DEBUG
    //     NSLog(@"Sending guild subscription for guild %@ and channel %@", guildId, channelId);
    // #endif
    [self sendJSON:@{
        @"op" : @(DCGatewayOpCodeGuildSubscriptions),
        @"d" : @{
            @"guild_id" : guildId,
            @"typing" : @YES,
            @"threads" : @YES,
            @"activities" : @YES,
            @"thread_member_lists" : @[],
            @"members" : @[],
            @"channels" : @{
                channelId : @[
                    @[ @0, @99 ]
                ]
            }
        }
    }];
}

- (void)handleDispatchWithResponse:(NSDictionary *)parsedJsonResponse {
    // get data
    NSDictionary *d = [parsedJsonResponse objectForKey:@"d"];

    // Get event type and sequence number
    NSString *t         = [parsedJsonResponse objectForKey:@"t"];
    self.sequenceNumber = [[parsedJsonResponse objectForKey:@"s"] integerValue];
    // NSLog(@"Got event %@", t);
    // received READY
    if (![[parsedJsonResponse objectForKey:@"t"] isKindOfClass:[NSString class]]) {
        return;
    }

    if ([t isEqualToString:READY]) {
        @autoreleasepool {
            [self handleReadyWithData:d];
        }
        return;
    } else if ([t isEqualToString:PRESENCE_UPDATE_EVENT]) {
        [self handlePresenceUpdateEventWithData:d];
        return;
    } else if ([t isEqualToString:RESUMED]) {
        self.didAuthenticate = true;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.alertView dismissWithClickedButtonIndex:0 animated:YES];
            [self dismissNotification];
        });
        return;
    } else if ([t isEqualToString:MESSAGE_CREATE]) {
        [self handleMessageCreateWithData:d];
        return;
    } else if ([t isEqualToString:MESSAGE_UPDATE]) {
        [self handleMessageUpdateWithData:d];
        return;
    } else if ([t isEqualToString:MESSAGE_DELETE]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:@"MESSAGE DELETE" object:self userInfo:d];
        });
        return;
    } else if ([t isEqualToString:MESSAGE_ACK]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:@"MESSAGE ACK" object:self];
        });
        return;
    } else if ([t isEqualToString:TYPING_START]) {
        if (![d[@"channel_id"] isEqualToString:self.selectedChannel.snowflake]
            || ![d[@"guild_id"] isEqualToString:self.selectedChannel.parentGuild.snowflake]) {
            DBGLOG(@"Ignoring typing start event for channel %@ in guild %@, not currently selected channel/guild", d[@"channel_id"], d[@"guild_id"]);
            return;
        }
        DBGLOG(@"Got typing start event for channel %@ in guild %@", d[@"channel_id"], d[@"guild_id"]);
        if (![DCServerCommunicator.sharedInstance.loadedUsers objectForKey:d[@"user_id"]]
            || [DCServerCommunicator.sharedInstance.loadedUsers objectForKey:d[@"user_id"]] == [NSNull null]) {
            [DCTools convertJsonUser:[d valueForKeyPath:@"member.user"] cache:YES];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter
                postNotificationName:@"TYPING START"
                              object:d[@"user_id"]];
        });
    } else if ([t isEqualToString:GUILD_CREATE]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            for (DCGuild *g in self.guilds) {
                if ([g.snowflake isEqualToString:[d objectForKey:@"id"]]) {
                    DBGLOG(@"Guild with ID %@ ready for member list!", [d objectForKey:@"id"]);
                    return;
                }
            }
            [self.guilds addObject:[DCTools convertJsonGuild:d withMembers:nil]];
            self.guildsIsSorted = NO;
        });
        return;
    } else if ([t isEqualToString:THREAD_CREATE] || [t isEqualToString:CHANNEL_CREATE]) {
        [self handleChannelCreateWithData:d];
        return;
    } else if ([t isEqualToString:CHANNEL_UNREAD_UPDATE]) {
        if (!self.channels) {
            return;
        }
        NSArray *unreads = [d objectForKey:@"channel_unread_updates"];
        for (NSDictionary *unread in unreads) {
            NSString *channelId = [unread objectForKey:@"id"];
            DCChannel *channel  = [self.channels objectForKey:channelId];
            if (channel) {
                channel.lastMessageId = [unread objectForKey:@"last_message_id"];
                // #ifdef DEBUG
                //                 BOOL oldUnread        = channel.unread;
                [channel checkIfRead];
                //                 if (oldUnread != channel.unread) {
                //                     NSLog(@"Channel %@ (%@) unread state changed to %d", channel.name, channel.snowflake, channel.unread);
                //                 }
                // #endif
            }
        }
    } else if ([t isEqualToString:GUILD_MEMBER_LIST_UPDATE]) {
        [self handleGuildMemberListUpdateWithData:d];
        return;
    } else {
        DBGLOG(@"Unhandled event type: %@, content: %@", t, d);
        return;
    }
}

#pragma mark - WebSocket Handlers

- (void)startCommunicator {
    DBGLOG(@"Starting communicator!");

    [self.alertView show];
    self.didAuthenticate = false;
    self.oldMode         = [[NSUserDefaults standardUserDefaults] boolForKey:@"hackyMode"];

    // Dev
    [DCTools checkForAppUpdate];
    // Devend

    if (self.token == nil) {
        DBGLOG(@"No token set, cannot start communicator");
        return;
    }

    DBGLOG(@"Start websocket");

    // To prevent retain cycle
    __weak typeof(self) weakSelf = self;

    if (self.websocket) {
        DBGLOG(@"Websocket already open, not doing anything");
        return;
    }
    // Establish websocket connection with Discord
    NSURL *websocketUrl          = [NSURL URLWithString:self.gatewayURL];
    self.websocket               = [[WSWebSocket alloc] initWithURL:websocketUrl protocols:nil];
    self.websocket.closeCallback = ^(NSUInteger statusCode, NSString *message) {
        DBGLOG(@"Websocket closed with status code %lu and message: %@", (unsigned long)statusCode, message);
        if (statusCode == 1000) {
            // we closed it, do nothing
            return;
        } else if (statusCode == 2) {
            // kCFErrorDomainCFNetwork error 2 => DNS failure, likely not connected to the internet
            DBGLOG(@"DNS failure, likely not connected to the internet");
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.alertView setTitle:@"Waiting for connection..."];
                [NSTimer scheduledTimerWithTimeInterval:5
                                                 target:weakSelf
                                               selector:@selector(reconnect)
                                               userInfo:nil
                                                repeats:NO];
            });
        } else if (statusCode == 4004) {
            // invalid token, show alert and clear token
            dispatch_async(dispatch_get_main_queue(), ^{
                weakSelf.token = nil;
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Invalid Token"
                                                                    message:@"Your Discord token is invalid. Please retry with a valid token."
                                                                   delegate:weakSelf
                                                          cancelButtonTitle:@"Exit"
                                                          otherButtonTitles:nil];
                    alert.tag = 999;
                    [alert show];
                });
            });
        } else {
            // some other error, try to reconnect
            [weakSelf reconnect];
        }
    };
    // self.websocket.dataCallback = ^(NSData *data) {
    //     #ifdef DEBUG
    //         NSLog(@"Got data: %@", data);
    //     #endif
    // };
    // self.websocket.pongCallback = ^(void) {
    //     #ifdef DEBUG
    //         NSLog(@"Got pong");
    //     #endif
    // };
    // self.websocket.responseCallback = ^(NSHTTPURLResponse *response, NSData *data) {
    //     #ifdef DEBUG
    //         NSLog(@"Got response: %@", response);
    //     #endif
    //     // Check if the response is a 401 Unauthorized
    //     if (response.statusCode == 401) {
    //         DBGLOG(@"Unauthorized, closing websocket");
    //         [weakSelf.websocket close];
    //         weakSelf.websocket = nil;
    //         [DCTools alert:@"Unauthorized" withMessage:@"Your Discord token is invalid. Please re-authenticate."];
    //         return;
    //     }
    // };
    self.websocket.textCallback = ^(NSString *responseString) {
        // #ifdef DEBUG
        //     NSLog(@"Got response: %@", responseString);
        // #endif

        // Parse JSON to a dictionary
        NSDictionary *parsedJsonResponse = [DCTools parseJSON:responseString];
        // NSLog(responseString);

        // Data values for easy access
        int op          = [[parsedJsonResponse objectForKey:@"op"] integerValue];
        NSDictionary *d = [parsedJsonResponse objectForKey:@"d"];

        // #ifdef DEBUG
        //     NSLog(@"Got op code %i", op);
        // #endif

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            switch (op) {
                case DCGatewayOpCodeHello: {
                    [weakSelf handleHelloWithData:d];
                    break;
                }
                case DCGatewayOpCodeDispatch: {
                    [weakSelf handleDispatchWithResponse:parsedJsonResponse];
                    break;
                }
                case DCGatewayOpCodeHeartbeat: {
                    // ack with our own heartbeat
                    [weakSelf sendJSON:@{
                        @"op" : @(DCGatewayOpCodeHeartbeat),
                        @"d" : @(weakSelf.sequenceNumber)
                    }];
                    // fallthrough to HEARTBEAT_ACK
                }
                case DCGatewayOpCodeHeartbeatAck: {
#ifdef DEBUG
                    NSDate *now = [NSDate date];
                    NSDate *nextFireDate = heartbeatTimer.fireDate;
                    NSTimeInterval interval = heartbeatTimer.timeInterval;
                    NSDate *previousFireDate = [nextFireDate dateByAddingTimeInterval:-interval];
                    DBGLOG(@"Got heartbeat ack in %f seconds!", [now timeIntervalSinceDate:previousFireDate]);
#endif
                    weakSelf.gotHeartbeat = true;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
                    });
                    break;
                }
                case DCGatewayOpCodeReconnect: {
                    DBGLOG(@"Got RECONNECT, reconnecting...");
                    [weakSelf reconnect];
                    break;
                }
                case DCGatewayOpCodeInvalidSession: {
                    if ([(NSNumber *)d boolValue]) {
                        // If the session is valid, we can resume (rare)
                        DBGLOG(@"INVALID_SESSION: Session is valid, resuming...");
                    } else {
                        // If the session is invalid, we need to reconnect and start a new session
                        DBGLOG(@"INVALID_SESSION: Session was invalidated, re-identifying...");
                        weakSelf.sequenceNumber = 0;
                        weakSelf.sessionId      = nil;
                    }
                    [weakSelf reconnect];
                    break;
                }
                default: {
                    DBGLOG(@"Unhandled op code: %i, content: %@", op, d);
                    break;
                }
            }
        });
    };

    [self.websocket open];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 999 && buttonIndex == 0) {
        // following code by https://stackoverflow.com/a/17802404

        //home button press programmatically
        UIApplication *app = [UIApplication sharedApplication];
        [app performSelector:@selector(suspend)];
    
        //wait 2 seconds while app is going background
        [NSThread sleepForTimeInterval:2.0];
    
        //exit app when app is in background
        exit(EXIT_SUCCESS);
    }
}

- (void)reconnect {
    DBGLOG(@"Identify cooldown %s", self.canIdentify ? "true" : "false");

    dispatch_async(dispatch_get_main_queue(), ^{
        [heartbeatTimer invalidate]; // Invalidate because we're disconnected
        heartbeatTimer = nil;
    });
    // Begin new session
    [self.websocket close];
    self.websocket = nil;
    if (self.oldMode == NO) {
        [self showNonIntrusiveNotificationWithTitle:@"Reconnecting..."];
    } else {
        [self.alertView show];
    }

    // If an identify cooldown is in effect, wait for the time needed until sending another IDENTIFY
    // if not, send immediately
    NSTimeInterval timeRemaining = [self.cooldownTimer.fireDate timeIntervalSinceNow];
    if (self.canIdentify || timeRemaining <= 0) {
        DBGLOG(@"No cooldown in effect. Authenticating...");
        [self.alertView setTitle:@"Authenticating..."];
        [self startCommunicator];
    } else {
        DBGLOG(@"Cooldown in effect. Time left %lf", timeRemaining);
        [self.alertView setTitle:@"Waiting for auth cooldown..."];
        if (self.oldMode == NO) {
            [self showNonIntrusiveNotificationWithTitle:@"Awaiting cooldown..."];
        }
        [self performSelector:@selector(reconnect) withObject:nil afterDelay:timeRemaining + 1];
    }

    self.canIdentify = false;
}

- (void)jitterBeat:(NSTimer *)timer {
    self.gotHeartbeat = false;
    [self sendJSON:@{
        @"op" : @(DCGatewayOpCodeHeartbeat),
        @"d" : @(self.sequenceNumber)
    }];
    DBGLOG(@"Sending jitterbeat, starting heartbeat cycle");
    // Begin heartbeat cycle
    float heartbeatInterval = [[timer.userInfo objectForKey:@"heartbeatInterval"] floatValue];
    dispatch_async(dispatch_get_main_queue(), ^{
        heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:heartbeatInterval
                                                          target:self
                                                        selector:@selector(sendHeartbeat:)
                                                        userInfo:nil
                                                         repeats:YES];
    });
}

- (void)sendHeartbeat:(NSTimer *)timer {
    // Check that we've recieved a response since the last heartbeat
    if (self.gotHeartbeat) {
        [self sendJSON:@{
            @"op" : @(DCGatewayOpCodeHeartbeat),
            @"d" : @(self.sequenceNumber)
        }];
        DBGLOG(@"Sent heartbeat");
        self.gotHeartbeat = false;
    } else {
        // If we didnt get a response in between heartbeats, we've disconnected from the websocket
        // send a RESUME to reconnect
        DBGLOG(@"Did not get heartbeat response before next heartbeat, sending RESUME with sequence %li %@ (sendHeartbeat)", (long)self.sequenceNumber, self.sessionId);
        [self reconnect];
    }
}

// Once the 5 second identify cooldown is over
- (void)refreshcanIdentify:(NSTimer *)timer {
    self.canIdentify = true;
    DBGLOG(@"Authentication cooldown ended");
}

- (void)sendJSON:(NSDictionary *)dictionary {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *writeError = nil;

        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dictionary options:NSJSONWritingPrettyPrinted error:&writeError];

        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        [self.websocket sendText:jsonString];
    });
}

- (void)description {
    NSLog(@"DCServerCommunicator lengths: \n"
           "channels: %lu (element %zu)\n"
           "guilds: %lu (element %zu)\n"
           "loadedUsers: %lu (element %zu)\n"
           "loadedRoles: %lu (element %zu)\n",
          (unsigned long)self.channels.count, malloc_size((__bridge const void *)(self.channels.allValues.firstObject)), (unsigned long)self.guilds.count, malloc_size((__bridge const void *)(self.guilds.firstObject)), (unsigned long)self.loadedUsers.count, malloc_size((__bridge const void *)(self.loadedUsers.allValues.firstObject)), (unsigned long)self.loadedRoles.count, malloc_size((__bridge const void *)(self.loadedRoles.allValues.firstObject)));
}

@end