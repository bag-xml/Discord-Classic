//
//  DCContentManager.m
//  Discord Classic
//
//  Created by Ayeris on 4/14/26.
//  Copyright (c) 2026 Ayeris. All rights reserved.
//

#import "DCContentManager.h"
#import "DCUser.h"
#import "UILazyImage.h"
#import "DCEmoji.h"
#include "SDWebImageManager.h"

@implementation DCContentManager

+ (instancetype)sharedInstance {
    static DCContentManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DCContentManager new];
    });
    return instance;
}

// --- Generic image processing ---

+ (UIImage *)roundedImage:(UIImage *)image size:(CGFloat)size {
    if (!image) return nil;
    CGSize targetSize = CGSizeMake(size, size);
    UIGraphicsBeginImageContextWithOptions(targetSize, NO, [UIScreen mainScreen].scale);
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, size, size)] addClip];
    [image drawInRect:CGRectMake(0, 0, size, size)];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

// --- Avatar processing ---

+ (UIImage *)processedAvatarForUser:(DCUser *)user context:(DCAssetContext)context {
    if (!user) return nil;

    CGFloat avatarSize, canvasSize;
    CGFloat chromeWidth, chromeHeight;
    NSString *chromeName;
    BOOL includeDecoration = YES;

    switch (context) {
        case DCAssetContextChat:
            avatarSize   = 38;
            canvasSize   = 46;
            chromeWidth  = 38;
            chromeHeight = 39;
            chromeName   = @"PFPInset";
            break;
        case DCAssetContextList:
            avatarSize   = 30;
            canvasSize   = 36;
            chromeWidth  = 30;
            chromeHeight = 31;
            chromeName   = @"sinkInMask";
            break;
        case DCAssetContextProfile:
            avatarSize        = 80;
            canvasSize        = 82;
            chromeWidth       = 82;
            chromeHeight      = 82;
            chromeName        = @"pfpOverlay";
            includeDecoration = NO;
            break;
    }

    CGFloat padding = (canvasSize - avatarSize) / 2.0;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(canvasSize, canvasSize), NO, [UIScreen mainScreen].scale);

    UIImage *rounded = [self roundedImage:user.rawProfileImage size:avatarSize];
    if (rounded) {
        [rounded drawInRect:CGRectMake(padding, padding, avatarSize, avatarSize)];
    }

    if (includeDecoration
        && user.avatarDecoration
        && [user.avatarDecoration isKindOfClass:[UIImage class]]
        && user.avatarDecoration.size.width > 0) {
        [user.avatarDecoration drawInRect:CGRectMake(0, 0, canvasSize, canvasSize)];
    }

    UIImage *chrome = [UIImage imageNamed:chromeName];
    if (chrome) {
        CGFloat chromeX = (canvasSize - chromeWidth) / 2.0;
        CGFloat chromeY = (canvasSize - chromeHeight) / 2.0;
        [chrome drawInRect:CGRectMake(chromeX, chromeY, chromeWidth, chromeHeight)];
    }

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

// --- DM Icon processing ---

+ (UIImage *)processedIcon:(UIImage *)image context:(DCAssetContext)context {
    if (!image) return nil;

    CGFloat avatarSize, canvasSize;
    CGFloat chromeWidth, chromeHeight;
    NSString *chromeName;

    switch (context) {
        case DCAssetContextChat:
            avatarSize   = 38;
            canvasSize   = 46;
            chromeWidth  = 38;
            chromeHeight = 39;
            chromeName   = @"PFPInset";
            break;
        case DCAssetContextList:
            avatarSize   = 30;
            canvasSize   = 36;
            chromeWidth  = 30;
            chromeHeight = 31;
            chromeName   = @"sinkInMask";
            break;
        case DCAssetContextProfile:
            avatarSize   = 80;
            canvasSize   = 82;
            chromeWidth  = 82;
            chromeHeight = 82;
            chromeName   = @"pfpOverlay";
            break;
    }

    CGFloat padding = (canvasSize - avatarSize) / 2.0;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(canvasSize, canvasSize), NO, [UIScreen mainScreen].scale);

    UIImage *rounded = [self roundedImage:image size:avatarSize];
    if (rounded) {
        [rounded drawInRect:CGRectMake(padding, padding, avatarSize, avatarSize)];
    }

    UIImage *chrome = [UIImage imageNamed:chromeName];
    if (chrome) {
        CGFloat chromeX = (canvasSize - chromeWidth) / 2.0;
        CGFloat chromeY = (canvasSize - chromeHeight) / 2.0;
        [chrome drawInRect:CGRectMake(chromeX, chromeY, chromeWidth, chromeHeight)];
    }

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

// --- Attachment images ---

+ (UILazyImage *)scaledAttachmentImage:(UIImage *)image withURL:(NSURL *)url {
    if (!image) return nil;
    if (image.images.count > 1) {
        // Animated GIF — don't scale, just wrap
        UILazyImage *lazyImage = [UILazyImage new];
        lazyImage.image        = image;
        lazyImage.imageURL     = url;
        return lazyImage;
    }
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat maxWidth    = screenWidth - 66;
    CGFloat aspectRatio = image.size.width / image.size.height;
    int newWidth        = (int)(200 * aspectRatio);
    int newHeight       = 200;
    if (newWidth > maxWidth) {
        newWidth  = (int)maxWidth;
        newHeight = (int)(newWidth / aspectRatio);
    }
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(newWidth, newHeight), NO, 0.0);
    [image drawInRect:CGRectMake(0, 0, newWidth, newHeight)];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    // Round attachment corners
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(newWidth, newHeight), NO, 0.0);
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, newWidth, newHeight)
                                cornerRadius:6] addClip];
    [scaled drawInRect:CGRectMake(0, 0, newWidth, newHeight)];
    UILazyImage *result = [UILazyImage new];
    result.image        = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    result.imageURL = url;
    return result;
}

// --- Emoji processing ---

+ (void)fetchEmojiImage:(DCEmoji *)emoji {
    if (!emoji || !emoji.snowflake) return;
    if (emoji.image && emoji.image.size.width > 0) return; // already loaded
    if (emoji.image) return;                               // sentinel set, download in progress

    emoji.image = [UIImage new]; // sentinel to block duplicate fetches

    NSString *ext    = emoji.animated ? @"gif" : @"png";
    NSURL *emojiURL  = [NSURL URLWithString:[NSString stringWithFormat:
        @"https://cdn.discordapp.com/emojis/%@.%@?size=32", emoji.snowflake, ext]];

    [[SDWebImageManager sharedManager]
        downloadImageWithURL:emojiURL
                     options:SDWebImageRetryFailed
                    progress:nil
                   completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                       if (!image || !finished) {
                           NSLog(@"[DCContentManager] Failed to load emoji '%@': %@", emoji.name, error);
                           emoji.image = nil; // clear sentinel so a retry is possible
                           return;
                       }
                       emoji.image = image;
                       dispatch_async(dispatch_get_main_queue(), ^{
                           [[NSNotificationCenter defaultCenter]
                               postNotificationName:@"EMOJI IMAGE READY"
                                             object:emoji.snowflake];
                       });
                   }];
}

@end