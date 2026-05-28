//
//  DCContentManager.h
//  Discord Classic
//
//  Created by Ayeris on 4/14/26.
//  Copyright (c) 2026 Ayeris. All rights reserved.
//

#import <UIKit/UIKit.h>

@class DCUser;
@class DCEmoji;
@class UILazyImage;

typedef NS_ENUM(NSInteger, DCAssetContext) {
    DCAssetContextChat,       // 46pt canvas, 38pt avatar, 38x39 chrome
    DCAssetContextList,       // 36pt canvas, 30pt avatar, 30x31 chrome
    DCAssetContextProfile,    // 96pt canvas, 80pt avatar, 82x82 chrome (no decoration)
};

@interface DCContentManager : NSObject

+ (instancetype)sharedInstance;

// --- Avatar processing ---
+ (UIImage *)processedAvatarForUser:(DCUser *)user context:(DCAssetContext)context;

// --- DM Icon processing ---
+ (UIImage *)processedIcon:(UIImage *)image context:(DCAssetContext)context;

// --- Generic image processing ---
+ (UIImage *)roundedImage:(UIImage *)image size:(CGFloat)size;

// --- Attachment images ---
+ (UILazyImage *)scaledAttachmentImage:(UIImage *)image withURL:(NSURL *)url;

// --- Emoji images ---
+ (void)fetchEmojiImage:(DCEmoji *)emoji;

@end