//
//  DCUser.m
//  Discord Classic
//
//  Created by Trevir on 11/17/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import "DCUser.h"
#import "DCGuild.h"

@implementation DCUser

+ (NSArray *)defaultAvatars {
    static NSArray *_defaultAvatars;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _defaultAvatars = @[
            [UIImage imageNamed:@"DefaultAvatar0"],
            [UIImage imageNamed:@"DefaultAvatar1"],
            [UIImage imageNamed:@"DefaultAvatar2"],
            [UIImage imageNamed:@"DefaultAvatar3"],
            [UIImage imageNamed:@"DefaultAvatar4"],
            [UIImage imageNamed:@"DefaultAvatar5"],
        ];
    });
    return _defaultAvatars;
}

+ (DCUserStatus)statusFromString:(NSString *)statusString {
    if ([statusString isEqualToString:@"online"]) {
        return DCUserStatusOnline;
    } else if ([statusString isEqualToString:@"idle"]) {
        return DCUserStatusIdle;
    } else if ([statusString isEqualToString:@"dnd"]) {
        return DCUserStatusDoNotDisturb;
    } else {
        return DCUserStatusOffline;
    }
}

+ (NSString *)stringFromStatus:(DCUserStatus)status {
    switch (status) {
        case DCUserStatusOnline:
            return @"online";
        case DCUserStatusIdle:
            return @"idle";
        case DCUserStatusDoNotDisturb:
            return @"dnd";
        case DCUserStatusOffline:
        default:
            return @"offline";
    }
}

- (NSString *)description {
    return [NSString
        stringWithFormat:@"[User] Snowflake: %@, Username: %@, Display name %@",
                         self.snowflake, self.username, self.globalName];
}

- (NSString *)displayName {
    if (self.globalName && self.globalName.length > 0) {
        return self.globalName;
    }
    return self.username;
}

- (NSString *)displayNameInGuild:(DCGuild *)guild {
    if (guild && self.guildNicknames) {
        NSString *nick = self.guildNicknames[guild.snowflake];
        if (nick && nick.length > 0) {
            return nick;
        }
    }
    return [self displayName];
}
@end
