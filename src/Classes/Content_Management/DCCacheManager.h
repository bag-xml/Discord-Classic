//
//  DCCacheManager.h
//  Discord Classic
//
//  Created by Ayeris on 3/20/26.
//  Copyright (c) 2026 Ayeris All rights reserved.
//

#import <UIKit/UIKit.h>

@class DCMessage;
@class DCUser;
@class DCEmoji;

@interface DCMessageCacheEntry : NSObject
@property (nonatomic) CGFloat cellHeight;
@property (nonatomic) CGFloat contentHeight;
@property (nonatomic) CGFloat textHeight;
@property (strong, nonatomic) NSAttributedString *attributedContent;
@end

@interface DCCacheManager : NSObject

+ (instancetype)sharedInstance;

// --- Message cache ---
// Store and retrieve full cache entry for a message
- (DCMessageCacheEntry *)cacheEntryForSnowflake:(NSString *)snowflake width:(CGFloat)width;
- (void)setCacheEntry:(DCMessageCacheEntry *)entry forSnowflake:(NSString *)snowflake width:(CGFloat)width;

// Targeted invalidation
- (void)invalidateSnowflake:(NSString *)snowflake;

// Full flush — use on memory warning or channel change
- (void)invalidateAllMessages;

// --- Avatar cache ---
- (UIImage *)avatarForUserSnowflake:(NSString *)snowflake;
- (void)setAvatar:(UIImage *)image forUserSnowflake:(NSString *)snowflake;

// --- Avatar decoration cache ---
- (UIImage *)decorationForUserSnowflake:(NSString *)snowflake;
- (void)setDecoration:(UIImage *)image forUserSnowflake:(NSString *)snowflake;

// --- Emoji cache ---
- (UIImage *)imageForEmojiSnowflake:(NSString *)snowflake;
- (void)setImage:(UIImage *)image forEmojiSnowflake:(NSString *)snowflake;

// --- Memory management ---
- (void)handleMemoryWarning;

@end