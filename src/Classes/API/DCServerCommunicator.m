//
//  DCServerCommunicator.m
//  Discord Classic
//
//  Created by bag.xml on 3/4/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import "DCServerCommunicator.h"
#include "DCGuildFolder.h"
#include <objc/NSObjCRuntime.h>
#include "DCRole.h"
#include <dispatch/dispatch.h>
#include <Foundation/Foundation.h>
#import "DCChannel.h"
#import "DCGuild.h"
#import "DCTools.h"

@interface DCServerCommunicator ()
@property (strong, nonatomic) UIView *notificationView;
@property bool didReceiveHeartbeatResponse;
@property bool didTryResume;
@property bool shouldResume;
@property bool heartbeatDefined;

@property bool identifyCooldown;

@property int sequenceNumber;
@property NSString *sessionId;

@property NSTimer *cooldownTimer;
@property UIAlertView *alertView;
@property bool oldMode;
+ (DCServerCommunicator *)sharedInstance;
- (void)showNonIntrusiveNotificationWithTitle:(NSString *)title;
- (void)dismissNotification;
@end


@implementation DCServerCommunicator

UIActivityIndicatorView *spinner;

+ (DCServerCommunicator *)sharedInstance {
    static DCServerCommunicator *sharedInstance = nil;

    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
#ifdef DEBUG
        NSLog(@"[DCServerCommunicator] Creating shared instance");
#endif
        sharedInstance = [[self alloc] init];

        // Initialize if a sharedInstance does not yet exist

        sharedInstance.gatewayURL      = @"wss://gateway.discord.gg/?encoding=json&v=9";
        sharedInstance.oldMode         = [[NSUserDefaults standardUserDefaults] boolForKey:@"hackyMode"];
        sharedInstance.token           = [[NSUserDefaults standardUserDefaults] stringForKey:@"token"];
        sharedInstance.currentUserInfo = nil;

        if ([sharedInstance.token length] == 0) {
            return;
        }

        if (sharedInstance.oldMode == YES) {
            sharedInstance.alertView = [UIAlertView.alloc initWithTitle:@"Connecting" message:@"\n" delegate:self cancelButtonTitle:nil otherButtonTitles:nil];

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
    dispatch_async(dispatch_get_main_queue(), ^{
        self.didAuthenticate = true;
#ifdef DEBUG
        NSLog(@"Did authenticate!");
#endif
        [self dismissNotification];
        // Grab session id (used for RESUME) and user id
        self.sessionId = [NSString stringWithFormat:@"%@", [d valueForKeyPath:@"session_id"]];
        // THIS IS US, hey hey hey this is MEEEEE BITCCCH MORTY DID YOU HEAR, THIS IS ME, AND MY USER ID, YES MORT(BUÜÜÜRPP)Y, THIS IS ME. BITCCHHHH. 100 YEARS OF DISCORD CLASSIC MORTYY YOU AND MEEEE
        self.snowflake                = [NSString stringWithFormat:@"%@", [d valueForKeyPath:@"user.id"]];
        NSMutableDictionary *userInfo = [NSMutableDictionary new];
        userInfo[@"username"]         = [d valueForKeyPath:@"user.username"];
        if ([[d valueForKeyPath:@"user.global_name"] isKindOfClass:[NSNull class]]) {
            userInfo[@"global_name"] = [d valueForKeyPath:@"user.username"];
        } else {
            userInfo[@"global_name"] = [d valueForKeyPath:@"user.global_name"];
        }
        userInfo[@"pronouns"]          = [d valueForKeyPath:@"user.pronouns"];
        userInfo[@"avatar"]            = [d valueForKeyPath:@"user.avatar"];
        userInfo[@"phone"]             = [d valueForKeyPath:@"user.phone"];
        userInfo[@"email"]             = [d valueForKeyPath:@"user.email"];
        userInfo[@"bio"]               = [d valueForKeyPath:@"user.bio"];
        userInfo[@"banner"]            = [d valueForKeyPath:@"user.banner"];
        userInfo[@"banner_color"]      = [d valueForKeyPath:@"user.banner_color"];
        userInfo[@"clan"]              = [d valueForKeyPath:@"user.clan"];
        userInfo[@"id"]                = [d valueForKeyPath:@"user.id"];
        userInfo[@"connectedAccounts"] = [d valueForKeyPath:@"connected_accounts"];
        userInfo[@"guildPositions"]    = NSMutableArray.new;
        if ([d valueForKeyPath:@"user_settings.guild_positions"]) {
            [userInfo[@"guildPositions"] addObjectsFromArray:[d valueForKeyPath:@"user_settings.guild_positions"]];
        } else if ([d valueForKeyPath:@"user_settings.guild_folders"]) {
            userInfo[@"guildFolders"] = NSMutableArray.new;
            for (NSDictionary *userDict in [d valueForKeyPath:@"user_settings.guild_folders"]) {
                DCGuildFolder *folder = [DCGuildFolder new];
                folder.id = [userDict objectForKey:@"id"] != [NSNull null] ? [[userDict objectForKey:@"id"] intValue] : 0;
                folder.name = [userDict objectForKey:@"name"];
                folder.color = [userDict objectForKey:@"color"] != [NSNull null] ? [[userDict objectForKey:@"color"] intValue] : 0;
                folder.guildIds = [userDict objectForKey:@"guild_ids"];
                NSNumber *opened = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:[@(folder.id) stringValue]] objectForKey:@"opened"];
                folder.opened = opened != nil ? [opened boolValue] : YES; // default to opened
                [userInfo[@"guildFolders"] addObject:folder];
                [userInfo[@"guildPositions"] addObjectsFromArray:folder.guildIds];
            }
        } else {
            NSLog(@"no guild positions found in user settings");
        }
        self.currentUserInfo     = userInfo;
        self.userChannelSettings = NSMutableDictionary.new;
        for (NSDictionary *guildSettings in [d objectForKey:@"user_guild_settings"]) {
            for (NSDictionary *channelSetting in [guildSettings objectForKey:@"channel_overrides"]) {
                [self.userChannelSettings setValue:@((bool)[channelSetting objectForKey:@"muted"]) forKey:[channelSetting objectForKey:@"channel_id"]];
            }
        }
        // Get user DMs and DM groups
        // The user's DMs are treated like a guild, where the channels are different DM/groups
        DCGuild *privateGuild = DCGuild.new;
        privateGuild.name     = @"Direct Messages";
        if (self.oldMode == NO) {
            privateGuild.icon = [UIImage imageNamed:@"privateGuildLogo"];
        }
        privateGuild.channels = NSMutableArray.new;
        for (NSDictionary *privateChannel in [d objectForKey:@"private_channels"]) {
            // this may actually suck
            //  Initialize users array for the member list
            NSMutableArray *users = NSMutableArray.new;
            // NSLog(@"%@", privateChannel);
            NSMutableDictionary *usersDict;
            DCChannel *newChannel    = DCChannel.new;
            newChannel.parentID      = [privateChannel objectForKey:@"parent_id"];
            newChannel.snowflake     = [privateChannel objectForKey:@"id"];
            newChannel.lastMessageId = [privateChannel objectForKey:@"last_message_id"];
            newChannel.parentGuild   = privateGuild;
            newChannel.type          = 1;
            newChannel.users         = users;
            newChannel.writeable     = YES; // DMs are always writeable
            if ([privateChannel objectForKey:@"icon"] != nil || [privateChannel objectForKey:@"recipients"] != nil) {
                if (((NSArray *)[privateChannel objectForKey:@"recipients"]).count > 0) {
                    NSDictionary *user    = [[privateChannel objectForKey:@"recipients"] objectAtIndex:0];
                    newChannel.recipients = [privateChannel objectForKey:@"recipients"];
                    for (NSDictionary *user in [privateChannel objectForKey:@"recipients"]) {
                        usersDict = NSMutableDictionary.new;
                        [usersDict setObject:[user objectForKey:@"global_name"] forKey:@"username"];
                        [usersDict setObject:[user objectForKey:@"username"] forKey:@"handle"];
                        [usersDict setObject:[user objectForKey:@"avatar"] forKey:@"avatar"];
                        [usersDict setObject:[user objectForKey:@"id"] forKey:@"snowflake"];
                        [users addObject:usersDict];
                        // Ensure user is added to loadedUsers
                        NSString *userId = [user objectForKey:@"id"];
                        if (userId && ![self.loadedUsers objectForKey:userId]) {
                            DCUser *dcUser = [DCTools convertJsonUser:user cache:YES]; // Add to loadedUsers
                            [self.loadedUsers setObject:dcUser forKey:userId];
                            // NSLog(@"[READY] Cached user: %@ (ID: %@)", dcUser.username, dcUser.snowflake);
                        }
                    }
                    // Add self to users list
                    usersDict = NSMutableDictionary.new;
                    [usersDict setObject:[NSString stringWithFormat:@"You"] forKey:@"username"];
                    [usersDict setObject:[user objectForKey:@"avatar"] forKey:@"avatar"];
                    [usersDict setObject:[user objectForKey:@"id"] forKey:@"snowflake"];
                    [users addObject:usersDict];
                    // end
                    /*NSMutableDictionary *usersDict;
                     for (NSDictionary* user in [privateChannel objectForKey:@"recipients"]) {
                     usersDict = NSMutableDictionary.new;
                     [usersDict setObject:[user objectForKey:@"username"] forKey:@"username"];
                     [usersDict setObject:[user objectForKey:@"avatar"] forKey:@"avatar"];
                     [users addObject:usersDict];
                     }*/
                    NSNumber *longId = @([[user objectForKey:@"id"] longLongValue]);
                    int selector     = (int)(([longId longLongValue] >> 22) % 6);
                    newChannel.icon  = [DCUser defaultAvatars][selector];
                    CGSize itemSize  = CGSizeMake(32, 32);
                    UIGraphicsBeginImageContextWithOptions(itemSize, NO, UIScreen.mainScreen.scale);
                    CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
                    [newChannel.icon drawInRect:imageRect];
                    newChannel.icon = UIGraphicsGetImageFromCurrentImageContext();
                    UIGraphicsEndImageContext();
                }
                if ([privateChannel objectForKey:@"icon"] != nil) {
                    NSString *iconURL    = [NSString stringWithFormat:@"https://cdn.discordapp.com/channel-icons/%@/%@.png?size=64",
                                                                   newChannel.snowflake, [privateChannel objectForKey:@"icon"]];
                    NSNumber *longId = @([newChannel.snowflake longLongValue]);
                    int selector     = (int)(([longId longLongValue] >> 22) % 6);
                    newChannel.icon  = [DCUser defaultAvatars][selector];
                    CGSize itemSize  = CGSizeMake(32, 32);
                    UIGraphicsBeginImageContextWithOptions(itemSize, NO, UIScreen.mainScreen.scale);
                    CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
                    [newChannel.icon drawInRect:imageRect];
                    newChannel.icon = UIGraphicsGetImageFromCurrentImageContext();
                    UIGraphicsEndImageContext();
                    [DCTools processImageDataWithURLString:iconURL
                                                  andBlock:^(UIImage *imageData) {
                                                      UIImage *icon = imageData;
                                                      if (icon == nil) {
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
                                                      //   /*[NSNotificationCenter.defaultCenter postNotificationName:@"RELOAD CHANNEL LIST" object:DCServerCommunicator.sharedInstance];*/
                                                  }];
                } else {
                    if (((NSArray *)[privateChannel objectForKey:@"recipients"]).count > 0) {
                        NSDictionary *user  = [[privateChannel objectForKey:@"recipients"] objectAtIndex:0];
                        NSString *avatarURL = [NSString
                            stringWithFormat:@"https://cdn.discordapp.com/avatars/%@/%@.png?size=64",
                                             [user objectForKey:@"id"],
                                             [user objectForKey:@"avatar"]];
                        [DCTools processImageDataWithURLString:avatarURL
                                                      andBlock:^(UIImage *imageData) {
                                                          UIImage *retrievedImage = imageData;
                                                          if (imageData) {
                                                              newChannel.icon = retrievedImage;
                                                              CGSize itemSize = CGSizeMake(32, 32);
                                                              dispatch_async(dispatch_get_main_queue(), ^{
                                                                  UIGraphicsBeginImageContextWithOptions(itemSize, NO, UIScreen.mainScreen.scale);
                                                                  CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
                                                                  [newChannel.icon drawInRect:imageRect];
                                                                  newChannel.icon = UIGraphicsGetImageFromCurrentImageContext();
                                                                  [NSNotificationCenter.defaultCenter postNotificationName:@"RELOAD CHANNEL LIST" object:nil];
                                                              });
                                                          } else {
                                                              int selector         = 0;
                                                              NSNumber *discriminator = @([[user objectForKey:@"discriminator"] integerValue]);
                                                              if ([discriminator integerValue] == 0) {
                                                                  NSNumber *longId = @([[user objectForKey:@"id"] longLongValue]);
                                                                  selector         = (int)(([longId longLongValue] >> 22) % 6);
                                                              } else {
                                                                  selector = (int)([discriminator integerValue] % 5);
                                                              }
                                                              newChannel.icon = [DCUser defaultAvatars][selector];
                                                              CGSize itemSize = CGSizeMake(32, 32);
                                                              dispatch_async(dispatch_get_main_queue(), ^{
                                                                UIGraphicsBeginImageContextWithOptions(itemSize, NO, UIScreen.mainScreen.scale);
                                                                CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
                                                                [newChannel.icon drawInRect:imageRect];
                                                                newChannel.icon = UIGraphicsGetImageFromCurrentImageContext();
                                                                UIGraphicsEndImageContext();
                                                              });
                                                          }
                                                          // Process user presences from READY payload
                                                          NSArray *presences = [d objectForKey:@"presences"];
                                                          for (NSDictionary *presence in presences) {
                                                              NSString *userId = [presence valueForKeyPath:@"user.id"];
                                                              NSString *status = [presence objectForKey:@"status"];
                                                              if (userId && status) {
                                                                  DCUser *user = [self.loadedUsers objectForKey:userId];
                                                                  if (user) {
                                                                      user.status = status;
                                                                      // NSLog(@"[READY] Updated user %@ (ID: %@) to status: %@", user.username, userId, user.status);
                                                                  } else {
                                                                      // NSLog(@"[READY] Presence received for unknown user ID: %@", userId);
                                                                  }
                                                              }
                                                          }
                                                      }];
                    }
                }
            }
            NSString *privateChannelName = [privateChannel objectForKey:@"name"];
            // Some private channels dont have names, check if nil
            if (privateChannelName && (NSNull *)privateChannelName != [NSNull null]) {
                newChannel.name = privateChannelName;
            } else {
                // If no name, create a name from channel members
                NSMutableString *fullChannelName = [@"" mutableCopy];
                NSArray *privateChannelMembers   = [privateChannel objectForKey:@"recipients"];
                for (NSDictionary *privateChannelMember in privateChannelMembers) {
                    // add comma between member names
                    if ([privateChannelMembers indexOfObject:privateChannelMember] != 0) {
                        [fullChannelName appendString:@", @"];
                    }
                    NSString *memberName = [privateChannelMember objectForKey:@"username"];
                    if ([privateChannelMember objectForKey:@"global_name"] 
                    && [[privateChannelMember objectForKey:@"global_name"] isKindOfClass:[NSString class]]) {
                        memberName = [privateChannelMember objectForKey:@"global_name"];
                    }
                    [fullChannelName appendString:memberName];
                    newChannel.name = fullChannelName;
                }
            }
            [privateGuild.channels addObject:newChannel];
        }
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
        for (NSDictionary *jsonGuild in [d objectForKey:@"guilds"]) {
            DCGuild *guild = [DCTools convertJsonGuild:jsonGuild];
            [guilds addObject:guild];
        }
        for (NSDictionary *guildSettings in [d objectForKey:@"user_guild_settings"]) {
            NSString *guildId = [guildSettings objectForKey:@"guild_id"];
            if ((NSNull *)guildId == [NSNull null]) {
                ((DCGuild *)guilds[0]).muted = [[guildSettings objectForKey:@"muted"] boolValue];
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
        [NSNotificationCenter.defaultCenter postNotificationName:@"READY" object:self];
        // Dismiss the 'reconnecting' dialogue box
        [self.alertView dismissWithClickedButtonIndex:0 animated:YES];
    });
}

- (void)handlePresenceUpdateEventWithData:(NSDictionary *)d {
    NSString *userId = [d valueForKeyPath:@"user.id"];
    NSString *status = [d objectForKey:@"status"];
    if (!userId || !status) {
        // NSLog(@"[PRESENCE_UPDATE] Missing user ID or status in payload: %@", d);
        return;
    }
    DCUser *user = [self.loadedUsers objectForKey:userId];
    if (user) {
        user.status = status;
        // NSLog(@"[PRESENCE_UPDATE] Updated user %@ (ID: %@) to status: %@", user.username, userId, user.status);
    } else {
        // Cache user if not already in loadedUsers
        NSDictionary *userDict = [d objectForKey:@"user"];
        if (userDict) {
            user = [DCTools convertJsonUser:userDict cache:YES];
            [self.loadedUsers setObject:user forKey:userId];
            user.status = status;
            // NSLog(@"[PRESENCE_UPDATE] Cached and updated user %@ (ID: %@) to status: %@", user.username, userId, user.status);
        }
    }
    // IMPORTANT: Post a notification so we can refresh DM status dots
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:@"USER_PRESENCE_UPDATED" object:user];
    });
}

- (void)handleMessageCreateWithData:(NSDictionary *)d {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *channelIdOfMessage = [d objectForKey:@"channel_id"];
        NSString *messageId          = [d objectForKey:@"id"];
        // Check if a channel is currently being viewed
        // and if so, if that channel is the same the message was sent in
        if (self.selectedChannel != nil && [channelIdOfMessage isEqualToString:self.selectedChannel.snowflake]) {
            // Send notification with the new message
            // will be recieved by DCChatViewController
            [NSNotificationCenter.defaultCenter postNotificationName:@"MESSAGE CREATE" object:self userInfo:d];
            // Update current channel & read state last message
            [self.selectedChannel setLastMessageId:messageId];
            // Ack message since we are currently viewing this channel
            [self.selectedChannel ackMessage:messageId];
        } else {
            DCChannel *channelOfMessage    = [self.channels objectForKey:channelIdOfMessage];
            channelOfMessage.lastMessageId = messageId;
            [channelOfMessage checkIfRead];
            [NSNotificationCenter.defaultCenter postNotificationName:@"MESSAGE ACK" object:self];
        }
    });
}

- (void)handleMessageUpdateWithData:(NSDictionary *)d {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *channelIdOfMessage = [d objectForKey:@"channel_id"];
        NSString *messageId          = [d objectForKey:@"id"];
        // Check if a channel is currently being viewed
        // and if so, if that channel is the same the message was sent in
        if (self.selectedChannel != nil && [channelIdOfMessage isEqualToString:self.selectedChannel.snowflake]) {
            // Send notification with the new message
            // will be recieved by DCChatViewController
            [NSNotificationCenter.defaultCenter postNotificationName:@"MESSAGE EDIT" object:self userInfo:d];
            // Update current channel & read state last message
            [self.selectedChannel setLastMessageId:messageId];
            // Ack message since we are currently viewing this channel
            [self.selectedChannel ackMessage:messageId];
        }
    });
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
        id ret = [self.loadedRoles objectForKey:[groupItem objectForKey:@"id"]];
        if (!ret) {
            // fake online/offline roles
            DCRole *role = DCRole.new;
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
        DCUser *user = [self.loadedUsers objectForKey:[memberItem valueForKeyPath:@"user.id"]];
        if (!user) {
            user = [DCTools convertJsonUser:[memberItem objectForKey:@"user"] cache:YES];
            [self.loadedUsers setObject:user forKey:user.snowflake];
        }
        user.status = [memberItem valueForKeyPath:@"presence.status"];
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
    dispatch_async(dispatch_get_main_queue(), ^{
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
        @synchronized (guild) {
            guild.memberCount = [[d objectForKey:@"member_count"] intValue];
            guild.onlineCount = [[d objectForKey:@"online_count"] intValue];
        }
        @synchronized (guild.members) {
            for (NSDictionary *op in [d objectForKey:@"ops"]) {
                if ([[op objectForKey:@"op"] isEqualToString:SYNC]) {
                    if (![[op objectForKey:@"items"] isKindOfClass:[NSArray class]] 
                        || [((NSArray *)[op objectForKey:@"items"]) count] == 0) {
#ifdef DEBUG
                        NSLog(@"Guild member list update SYNC op without items: %@", op);
#endif
                        continue;
                    }
                    guild.members = NSMutableArray.new;
// #ifdef DEBUG
//                     NSLog(
//                         @"SYNC: length: %lu, range: [%lu..%lu]", 
//                         (unsigned long)[op[@"items"] count],
//                         (unsigned long)[op[@"range"][0] integerValue],
//                         (unsigned long)[op[@"range"][1] integerValue]
//                     );
// #endif
                    for (NSDictionary *item in [op objectForKey:@"items"]) {
                        id member = [self handleGuildMemberItemWithItem:item];
                        if (!member) {
#ifdef DEBUG
                            NSLog(@"Guild member list update SYNC op with invalid item: %@", item);
#endif
                            continue;
                        }
                        [guild.members addObject:member];
                    }
                } else if ([[op objectForKey:@"op"] isEqualToString:UPDATE]) {
                    NSDictionary *item = [op objectForKey:@"item"];
                    id member = [self handleGuildMemberItemWithItem:item];
                    if (!member) {
#ifdef DEBUG
                        NSLog(@"Guild member list update UPDATE op with invalid item: %@", item);
#endif
                        continue;
                    }
                    NSUInteger index = [[op objectForKey:@"index"] intValue];
                    if (index >= [guild.members count]) {
                        index = [guild.members count] - 1;
                    } else if (index < 0) {
                        index = 0;
                    }
// #ifdef DEBUG
//                     NSLog(@"Updating %s at index: %lu", [member isKindOfClass:[DCUser class]] ? "user" : "role", (unsigned long)index);
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
//                     NSLog(@"Deleting at index: %lu", (unsigned long)index);
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
                    id member = [self handleGuildMemberItemWithItem:item];
                    if (!member) {
#ifdef DEBUG
                        NSLog(@"Guild member list update INSERT op with invalid item: %@", item);
#endif
                        continue;
                    }
// #ifdef DEBUG
//                     NSLog(@"Inserting %s at index: %lu", [member isKindOfClass:[DCUser class]] ? "user" : "role", (unsigned long)index);
// #endif
                    [guild.members insertObject:member atIndex:index];
                } else {
#ifdef DEBUG
                    NSLog(@"Unhandled guild member list update op: %@", op);
#endif
                }
            }
            if ([guild.members count] > 100) {
                // NSLog(@"Capping guild members at 100");
                guild.members = [[guild.members subarrayWithRange:NSMakeRange(0, 100)] mutableCopy];
            }
// #ifdef DEBUG
//             NSLog(@"size: %lu", (unsigned long)[guild.members count]);
// #endif
        }
        if (self.selectedChannel != nil && [self.selectedChannel.parentGuild.snowflake isEqualToString:guild.snowflake]) {
            [NSNotificationCenter.defaultCenter postNotificationName:@"GuildMemberListUpdated" object:nil];
        }
    });
}

#pragma mark - WebSocket Event Handlers

- (void)handleHelloWithData:(NSDictionary *)d {
    if (self.shouldResume) {
#ifdef DEBUG
        NSLog(@"Sending Resume with sequence number %i, session ID %@", self.sequenceNumber, self.sessionId);
#endif
        // RESUME
        if (!self.token || !self.sessionId) {
            [DCTools
                      alert:@"Warning"
                withMessage:@"Something is wrong with your Discord token or your connection. Please re-check everything and retry."];
            return;
        }
        [self sendJSON:@{
            @"op" : @RESUME,
            @"d" : @{
                @"token" : self.token,
                @"session_id" : self.sessionId,
                @"seq" : @(self.sequenceNumber),
            }
        }];
        self.shouldResume = false;
    } else {
        [self sendJSON:@{
            @"op" : @IDENTIFY,
            @"d" : @{
                @"token" : self.token,
                @"properties" : @{
                    @"os" : @"iOS",
                    @"$browser" : @"Discord iOS",
                },
                @"large_threshold" : @"50",
            }
        }];
        // Disable ability to identify until reenabled 5 seconds later.
        // API only allows once identify every 5 seconds
        self.identifyCooldown = false;
        /* do not initialize guilds and channels here,
           could cause concurrency issues while guilds and channels are being loaded */
        self.loadedUsers                                                  = NSMutableDictionary.new;
        self.loadedRoles                                                  = NSMutableDictionary.new;
        self.didReceiveHeartbeatResponse                                  = true;
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        int heartbeatInterval                                             = [[d objectForKey:@"heartbeat_interval"] intValue];
        dispatch_async(dispatch_get_main_queue(), ^{
            static dispatch_once_t once;
            dispatch_once(&once, ^{
                // NSLog(@"Heartbeat is %d seconds", heartbeatInterval/1000);
                // Begin heartbeat cycle if not already begun
                [NSTimer scheduledTimerWithTimeInterval:(float)heartbeatInterval / 1000 target:self selector:@selector(sendHeartbeat:) userInfo:nil repeats:YES];
            });
            // Reenable ability to identify in 5 seconds
            self.cooldownTimer = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(refreshIdentifyCooldown:) userInfo:nil repeats:NO];
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
        @"op" : @GUILD_SUBSCRIPTIONS,
        @"d" : @{
            @"guild_id" : guildId,
            @"typing" : @YES,
            @"threads" : @YES,
            @"activities" : @YES,
            @"thread_member_lists" : @[],
            @"members": @[],
            @"channels": @{
                channelId : @[
                    @[@0, @99]
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
    // NSLog(@"Got event %@ with sequence number %i", t, self.sequenceNumber);
    // received READY
    if (![[parsedJsonResponse objectForKey:@"t"] isKindOfClass:[NSString class]]) {
        return;
    }

    if ([t isEqualToString:READY]) {
        [self handleReadyWithData:d];
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
    } else if ([t isEqualToString:GUILD_CREATE]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            for (DCGuild *g in self.guilds) {
                if ([g.snowflake isEqualToString:[d objectForKey:@"id"]]) {
#ifdef DEBUG
                    NSLog(@"Guild with ID %@ ready for member list!", [d objectForKey:@"id"]);
#endif
                    return;
                }
            }
            [self.guilds addObject:[DCTools convertJsonGuild:d]];
            self.guildsIsSorted = NO;
        });
        return;
    } else if ([t isEqualToString:THREAD_CREATE] || [t isEqualToString:CHANNEL_CREATE]) {
        [self handleChannelCreateWithData:d];
        return;
    } else if ([t isEqualToString:CHANNEL_UNREAD_UPDATE]) {
        NSArray *unreads = [d objectForKey:@"channel_unread_updates"];
        for (NSDictionary *unread in unreads) {
            NSString *channelId = [unread objectForKey:@"id"];
            DCChannel *channel  = [self.channels objectForKey:channelId];
            if (channel) {
                channel.lastMessageId = [unread objectForKey:@"last_message_id"];
                BOOL oldUnread = channel.unread;
                [channel checkIfRead];
                if (oldUnread != channel.unread) {
                    NSLog(@"Channel %@ (%@) unread state changed to %d", channel.name, channel.snowflake, channel.unread);
                }
            }
        }
    } else if ([t isEqualToString:GUILD_MEMBER_LIST_UPDATE]) {
        [self handleGuildMemberListUpdateWithData:d];
        return;
    } else {
#ifdef DEBUG
        NSLog(@"Unhandled event type: %@, content: %@", t, d);
#endif
        return;
    }
}

#pragma mark - WebSocket Handlers

- (void)startCommunicator {
#ifdef DEBUG
    NSLog(@"Starting communicator!");
#endif

    [self.alertView show];
    self.didAuthenticate = false;
    self.oldMode         = [[NSUserDefaults standardUserDefaults] boolForKey:@"hackyMode"];
    // Dev
    [DCTools checkForAppUpdate];
    // Devend
    if (self.token == nil) {
#ifdef DEBUG
        NSLog(@"No token set, cannot start communicator");
#endif
        return;
    }

#ifdef DEBUG
    NSLog(@"Start websocket");
#endif

    // Establish websocket connection with Discord
    NSURL *websocketUrl = [NSURL URLWithString:self.gatewayURL];
    self.websocket      = [WSWebSocket.alloc initWithURL:websocketUrl protocols:nil];

    // To prevent retain cycle
    __weak typeof(self) weakSelf = self;

    [self.websocket setTextCallback:^(NSString *responseString) {
        // #ifdef DEBUG
        //         NSLog(@"Got response: %@", responseString);
        // #endif

        // Parse JSON to a dictionary
        NSDictionary *parsedJsonResponse = [DCTools parseJSON:responseString];
        // NSLog(responseString);

        // Data values for easy access
        int op          = [[parsedJsonResponse objectForKey:@"op"] integerValue];
        NSDictionary *d = [parsedJsonResponse objectForKey:@"d"];

        // #ifdef DEBUG
        //         NSLog(@"Got op code %i", op);
        // #endif

        switch (op) {
            case HELLO: {
                [weakSelf handleHelloWithData:d];
                break;
            }
            case DISPATCH: {
                [weakSelf handleDispatchWithResponse:parsedJsonResponse];
                break;
            }
            case HEARTBEAT_ACK: {
                weakSelf.didReceiveHeartbeatResponse                              = true;
                [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
                break;
            }
            case RECONNECT: {
                weakSelf.shouldResume = self.sequenceNumber > 0 && self.sessionId != nil;
                [weakSelf reconnect];
            }
            case INVALID_SESSION: {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf reconnect];
                });
                break;
            }
            default: {
#ifdef DEBUG
                NSLog(@"Got unknown op code %i, content: %@", op, d);
#endif
                break;
            }
        }
    }];

    [weakSelf.websocket open];
}


- (void)sendResume {
    if (self.oldMode == NO) {
        [self showNonIntrusiveNotificationWithTitle:@"Resuming..."];
    }
    [self.alertView setTitle:@"Resuming..."];
    self.didTryResume = true;
    self.shouldResume = true;
    [self startCommunicator];
}


- (void)reconnect {
#ifdef DEBUG
    NSLog(@"Identify cooldown %s", self.identifyCooldown ? "true" : "false");
#endif

    // Begin new session
    [self.websocket close];
    if (self.oldMode == NO) {
        [self showNonIntrusiveNotificationWithTitle:@"Re-Authenticating..."];
    } else {
        [self.alertView show];
    }

    // If an identify cooldown is in effect, wait for the time needed until sending another IDENTIFY
    // if not, send immediately
    if (self.identifyCooldown) {
#ifdef DEBUG
        NSLog(@"No cooldown in effect. Authenticating...");
#endif
        [self.alertView setTitle:@"Authenticating..."];
        [self startCommunicator];
    } else {
        NSTimeInterval timeRemaining = [self.cooldownTimer.fireDate timeIntervalSinceNow];
#ifdef DEBUG
        NSLog(@"Cooldown in effect. Time left %lf", timeRemaining);
#endif
        [self.alertView setTitle:@"Waiting for auth cooldown..."];
        if (self.oldMode == NO) {
            [self showNonIntrusiveNotificationWithTitle:@"Re-Authenticating..."];
        }
        [self performSelector:@selector(startCommunicator) withObject:nil afterDelay:timeRemaining + 1];
    }

    self.identifyCooldown = false;
}


- (void)sendHeartbeat:(NSTimer *)timer {
    // Check that we've recieved a response since the last heartbeat
    if (self.didReceiveHeartbeatResponse) {
        [NSTimer scheduledTimerWithTimeInterval:8 target:self selector:@selector(checkForRecievedHeartbeat:) userInfo:nil repeats:NO];
        [self sendJSON:@{@"op" : @1, @"d" : @(self.sequenceNumber)}];
#ifdef DEBUG
        NSLog(@"Sent heartbeat");
#endif
        [self setDidReceiveHeartbeatResponse:false];
        self.didTryResume = false;
    } else if (self.didTryResume) {
#ifdef DEBUG
        NSLog(@"Did not get resume, trying reconnect instead with sequence %i %@", self.sequenceNumber, self.sessionId);
#endif
        [self reconnect];
        self.didTryResume = false;
    } else {
        // If we didnt get a response in between heartbeats, we've disconnected from the websocket
        // send a RESUME to reconnect
#ifdef DEBUG
        NSLog(@"Did not get heartbeat response, sending RESUME with sequence %i %@ (sendHeartbeat)", self.sequenceNumber, self.sessionId);
#endif
        [self sendResume];
    }
}

- (void)checkForRecievedHeartbeat:(NSTimer *)timer {
    if (!self.didReceiveHeartbeatResponse) {
#ifdef DEBUG
        NSLog(@"Did not get heartbeat response, sending RESUME with sequence %i %@ (checkForRecievedHeartbeat)", self.sequenceNumber, self.sessionId);
#endif
        [self sendResume];
    }
}

// Once the 5 second identify cooldown is over
- (void)refreshIdentifyCooldown:(NSTimer *)timer {
    self.identifyCooldown = true;
#ifdef DEBUG
    NSLog(@"Authentication cooldown ended");
#endif
}

- (void)sendJSON:(NSDictionary *)dictionary {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *writeError = nil;

        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dictionary options:NSJSONWritingPrettyPrinted error:&writeError];

        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        [self.websocket sendText:jsonString];
    });
}

@end