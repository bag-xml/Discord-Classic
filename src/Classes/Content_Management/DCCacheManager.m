//
//  DCCacheManager.m
//  Discord Classic
//
//  Created by Ayeris on 3/20/26.
//  Copyright (c) 2026 Ayeris All rights reserved.
//

#import "DCCacheManager.h"

@implementation DCMessageCacheEntry
@end

@interface DCCacheManager ()
@property (strong, nonatomic) NSMutableDictionary *messageCache;
@property (strong, nonatomic) NSMutableDictionary *avatarCache;
@property (strong, nonatomic) NSMutableDictionary *decorationCache;
@property (strong, nonatomic) NSMutableDictionary *emojiCache;
@end

@implementation DCCacheManager

+ (instancetype)sharedInstance {
    static DCCacheManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DCCacheManager new];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _messageCache    = [NSMutableDictionary dictionary];
        _avatarCache     = [NSMutableDictionary dictionary];
        _decorationCache = [NSMutableDictionary dictionary];
        _emojiCache      = [NSMutableDictionary dictionary];
    }
    return self;
}

// --- Message cache ---

// DCMessageCahceEntry contains  4 properties: 
// cellHeight, contentHeight, textHeight, attributedContent

// Private helper
- (NSString *)cacheKeyForSnowflake:(NSString *)snowflake width:(CGFloat)width {
    return [NSString stringWithFormat:@"%@_%.0f", snowflake, width];
}

// Width-aware read
- (DCMessageCacheEntry *)cacheEntryForSnowflake:(NSString *)snowflake width:(CGFloat)width {
    if (!snowflake) return nil;
    return self.messageCache[[self cacheKeyForSnowflake:snowflake width:width]];
}

// Width-aware write
- (void)setCacheEntry:(DCMessageCacheEntry *)entry forSnowflake:(NSString *)snowflake width:(CGFloat)width {
    if (!snowflake || !entry) return;
    self.messageCache[[self cacheKeyForSnowflake:snowflake width:width]] = entry;
}

// Updated invalidateSnowflake — clears all width variants
- (void)invalidateSnowflake:(NSString *)snowflake {
    if (!snowflake) return;
    NSString *prefix = [snowflake stringByAppendingString:@"_"];
    NSArray *keys = [self.messageCache.allKeys copy];
    for (NSString *key in keys) {
        if ([key hasPrefix:prefix]) {
            [self.messageCache removeObjectForKey:key];
        }
    }
}

- (void)invalidateAllMessages {
    [self.messageCache removeAllObjects];
}

// --- Avatar cache ---

- (UIImage *)avatarForUserSnowflake:(NSString *)snowflake {
    if (!snowflake) return nil;
    return self.avatarCache[snowflake];
}

- (void)setAvatar:(UIImage *)image forUserSnowflake:(NSString *)snowflake {
    if (!snowflake || !image) return;
    self.avatarCache[snowflake] = image;
}

// --- Avatar decoration cache ---

- (UIImage *)decorationForUserSnowflake:(NSString *)snowflake {
    if (!snowflake) return nil;
    return self.decorationCache[snowflake];
}

- (void)setDecoration:(UIImage *)image forUserSnowflake:(NSString *)snowflake {
    if (!snowflake || !image) return;
    self.decorationCache[snowflake] = image;
}

// --- Emoji cache ---

- (UIImage *)imageForEmojiSnowflake:(NSString *)snowflake {
    if (!snowflake) return nil;
    return self.emojiCache[snowflake];
}

- (void)setImage:(UIImage *)image forEmojiSnowflake:(NSString *)snowflake {
    if (!snowflake || !image) return;
    self.emojiCache[snowflake] = image;
}

// --- Memory management ---

- (void)handleMemoryWarning {
    // Flush attributed content from message entries but keep heights
    // Heights are cheap to store and expensive to recalculate
    for (DCMessageCacheEntry *entry in self.messageCache.allValues) {
        entry.attributedContent = nil;
    }
    // Flush emoji images — these re-download automatically when needed
    [self.emojiCache removeAllObjects];
    // SDWebImage memory cache is handled separately by the app delegate
}

// --- Guild/structure cache (disk-backed) ---

- (NSString *)guildCachePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documents = [paths objectAtIndex:0];
    return [documents stringByAppendingPathComponent:@"dc_guild_cache.archive"];
}

- (void)saveGuilds:(NSArray *)guilds {
    if (!guilds.count) return;
    NSString *path = [self guildCachePath];
    @try {
        [NSKeyedArchiver archiveRootObject:guilds toFile:path];
    }
    @catch (NSException *e) {
        NSLog(@"[DCCacheManager] Guild cache save failed: %@", e);
        // Remove any partial file that may have been written
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

- (NSArray *)loadCachedGuilds {
    NSString *path = [self guildCachePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    @try {
        return [NSKeyedUnarchiver unarchiveObjectWithFile:path];
    }
    @catch (NSException *e) {
        NSLog(@"[DCCacheManager] Guild cache corrupt, discarding: %@", e);
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return nil;
    }
}

- (void)invalidateGuildCache {
    NSString *path = [self guildCachePath];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

// --- Display Layout cache (disk-backed) ---

- (NSString *)displayLayoutCachePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [[paths objectAtIndex:0] stringByAppendingPathComponent:@"dc_layout_cache.archive"];
}

- (void)saveDisplayLayout:(NSArray *)displayGuilds {
    if (!displayGuilds.count) return;
    NSString *path = [self displayLayoutCachePath];
    @try {
        [NSKeyedArchiver archiveRootObject:displayGuilds toFile:path];
    }
    @catch (NSException *e) {
        NSLog(@"[DCCacheManager] Layout cache save failed: %@", e);
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

- (NSArray *)loadDisplayLayout {
    NSString *path = [self displayLayoutCachePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    @try {
        return [NSKeyedUnarchiver unarchiveObjectWithFile:path];
    }
    @catch (NSException *e) {
        NSLog(@"[DCCacheManager] Layout cache corrupt, discarding: %@", e);
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return nil;
    }
}

// --- User Info cache (disk-backed) ---

- (NSString *)userInfoCachePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES);
    return [[paths objectAtIndex:0]
        stringByAppendingPathComponent:@"dc_userinfo_cache.archive"];
}

- (void)saveUserInfo:(DCUserInfo *)userInfo {
    if (!userInfo) return;
    NSString *path = [self userInfoCachePath];
    @try {
        [NSKeyedArchiver archiveRootObject:userInfo toFile:path];
    }
    @catch (NSException *e) {
        NSLog(@"[DCCacheManager] UserInfo cache save failed: %@", e);
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

- (DCUserInfo *)loadCachedUserInfo {
    NSString *path = [self userInfoCachePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    @try {
        return [NSKeyedUnarchiver unarchiveObjectWithFile:path];
    }
    @catch (NSException *e) {
        NSLog(@"[DCCacheManager] UserInfo cache corrupt, discarding: %@", e);
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return nil;
    }
}
@end