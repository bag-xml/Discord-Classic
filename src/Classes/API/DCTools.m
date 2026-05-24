//
//  DCWebImageOperations.m
//  Discord Classic
//
//  Created by bag.xml on 3/17/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import "DCTools.h"
#include <Foundation/Foundation.h>
#include <Foundation/NSObjCRuntime.h>
#include <dispatch/dispatch.h>
#include <objc/NSObjCRuntime.h>
#import "Base64.h"
#import "DCChatVideoAttachment.h"
#import "DCGifInfo.h"
#import "DCEmoji.h"
#import "DCMessage.h"
#import "DCRole.h"
#import "DCServerCommunicator.h"
#import "DCUser.h"
#import "NSString+Emojize.h"
#import "QuickLook/QuickLook.h"
#import "SDWebImageManager.h"
#include "TSMarkdownParser.h"
#import "DCMarkdownParser.h"
#import "ThumbHash.h"
#import "UIImage+animatedGIF.h"
#import "UILazyImage.h"
#import "DCContentManager.h"
#import "DTCoreTextLayouter.h"
#import "DTCoreTextLayoutFrame.h"

// https://discord.gg/X4NSsMC

@implementation DCTools

// Avatar image roundinator
// static UIImage *roundedImage(UIImage *image) {
//     CGFloat size = MIN(image.size.width, image.size.height);
//     CGRect rect  = CGRectMake(0, 0, size, size);
//     UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0);
//     [[UIBezierPath bezierPathWithOvalInRect:rect] addClip];
//     [image drawInRect:rect];
//     UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
//     UIGraphicsEndImageContext();
//     return result;
// }

// Attachment image roundinator
static UIImage *roundedCornerImage(UIImage *image, CGFloat radius) {
    CGRect rect = CGRectMake(0, 0, image.size.width, image.size.height);
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0);
    [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius] addClip];
    [image drawInRect:rect];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

// Returns a parsed NSDictionary from a json string or nil if something goes
// wrong
+ (NSDictionary *)parseJSON:(NSString *)json {
    __block id parsedResponse;
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSError *error = nil;
        NSData *encodedResponseString =
            [json dataUsingEncoding:NSUTF8StringEncoding];
        parsedResponse =
            [NSJSONSerialization JSONObjectWithData:encodedResponseString
                                            options:0
                                              error:&error];
    });
    if ([parsedResponse isKindOfClass:NSDictionary.class]) {
        return parsedResponse;
    }
    return nil;
}

+ (void)alert:(NSString *)title withMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertView *alert = [UIAlertView.alloc initWithTitle:title
                                                      message:message
                                                     delegate:nil
                                            cancelButtonTitle:@"OK"
                                            otherButtonTitles:nil];
        [alert show];
    });
}

// Used when making synchronous http requests
+ (NSData *)checkData:(NSData *)response withError:(NSError *)error {
    if (!response) {
        [DCTools alert:error.localizedDescription
            withMessage:error.localizedRecoverySuggestion];
        return nil;
    }
    return response;
}

// Converts an NSDictionary created from json representing a user into a DCUser
// object Also keeps the user in DCServerCommunicator.loadedUsers if cache:YES
+ (DCUser *)convertJsonUser:(NSDictionary *)jsonUser cache:(BOOL)cache {
    if (cache && [DCServerCommunicator.sharedInstance userForSnowflake:[jsonUser objectForKey:@"id"]]) {
        // return pre-cached
        return [DCServerCommunicator.sharedInstance userForSnowflake:[jsonUser objectForKey:@"id"]];
    }

    // NSLog(@"%@", jsonUser);
    DCUser *newUser    = DCUser.new;
    newUser.username   = [jsonUser objectForKey:@"username"];
    newUser.globalName = newUser.username;
    if ([jsonUser objectForKey:@"global_name"] &&
        [[jsonUser objectForKey:@"global_name"] isKindOfClass:[NSString class]]) {
        newUser.globalName = [jsonUser objectForKey:@"global_name"];
    }
    newUser.snowflake          = [jsonUser objectForKey:@"id"];
    newUser.avatarID           = [jsonUser objectForKey:@"avatar"];
    newUser.avatarDecorationID = [jsonUser valueForKeyPath:@"avatar_decoration_data.asset"];
    newUser.discriminator      = [[jsonUser objectForKey:@"discriminator"] integerValue];
    newUser.status             = DCUserStatusOffline;

    // Save to DCServerCommunicator.loadedUsers
    if (cache) {
        [DCServerCommunicator.sharedInstance setUser:newUser forSnowflake:newUser.snowflake];
    }

    return newUser;
}

+ (void)getUserAvatar:(DCUser *)user {
    @autoreleasepool {
        // Bail if already downloading
        if (user.profileImage && user.profileImage.size.width == 0) {
            return; // placeholder is set, download already in flight
        }
        
        user.profileImage     = [UIImage new];
        user.avatarDecoration = [UIImage new];

        if (!user.avatarID || (NSNull *)user.avatarID == [NSNull null]) {
            int selector = 0;
            if (user.discriminator == 0) {
                NSNumber *longId = @([user.snowflake longLongValue]);
                selector = ([longId longLongValue] >> 22) % 6;
            } else {
                selector = user.discriminator % 5;
            }
            user.profileImage = [DCContentManager processedIcon:[DCUser defaultAvatars][selector] context:DCAssetContextChat];
            dispatch_async(dispatch_get_main_queue(), ^{
                [NSNotificationCenter.defaultCenter
                    postNotificationName:@"RELOAD USER DATA"
                                  object:user];
            });
            return;
        }

        SDWebImageManager *manager = [SDWebImageManager sharedManager];
        NSURL *avatarURL = [NSURL URLWithString:[NSString stringWithFormat:
            @"https://cdn.discordapp.com/avatars/%@/%@.png?size=80",
            user.snowflake, user.avatarID]];

        [manager downloadImageWithURL:avatarURL
                              options:SDWebImageRetryFailed
                             progress:nil
                            completed:^(UIImage *retrievedImage, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                @autoreleasepool {
                                    if (!retrievedImage || !finished) {
                                        int selector = 0;
                                        if (user.discriminator == 0) {
                                            NSNumber *longId = @([user.snowflake longLongValue]);
                                            selector = ([longId longLongValue] >> 22) % 6;
                                        } else {
                                            selector = user.discriminator % 5;
                                        }
                                        user.profileImage = [DCContentManager processedIcon:[DCUser defaultAvatars][selector] context:DCAssetContextChat];
                                        dispatch_async(dispatch_get_main_queue(), ^{
                                            [NSNotificationCenter.defaultCenter
                                                postNotificationName:@"RELOAD USER DATA"
                                                              object:user];
                                        });
                                        return;
                                    }

                                    // Process avatar — if decoration is already loaded, composite now
                                    // Otherwise just round and store, decoration will composite when it arrives
                                    if (user.avatarDecoration && [user.avatarDecoration isKindOfClass:[UIImage class]]
                                        && user.avatarDecoration.size.width > 0) {
                                        user.rawProfileImage = retrievedImage;
                                        user.profileImage = [DCContentManager processedAvatarForUser:user context:DCAssetContextChat];
                                    } else {
                                        // avatar completion block — store raw, then process
                                        user.rawProfileImage = retrievedImage;
                                        user.profileImage = [DCContentManager processedAvatarForUser:user context:DCAssetContextChat];
                                    }

                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        [NSNotificationCenter.defaultCenter
                                            postNotificationName:@"RELOAD USER DATA"
                                                          object:user];
                                    });
                                }
                            }];

        if (!user.avatarDecorationID || (NSNull *)user.avatarDecorationID == [NSNull null]) {
            return;
        }

        NSURL *avatarDecorationURL = [NSURL URLWithString:[NSString stringWithFormat:
            @"https://cdn.discordapp.com/avatar-decoration-presets/%@.png?size=96&passthrough=false",
            user.avatarDecorationID]];

        [manager downloadImageWithURL:avatarDecorationURL
                              options:SDWebImageRetryFailed
                             progress:nil
                            completed:^(UIImage *retrievedImage, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                if (!retrievedImage || !finished) {
                                    NSLog(@"Failed to download avatar decoration: %@", error);
                                    return;
                                }
                                user.avatarDecoration = retrievedImage;
                                // Only recomposite if the base avatar has already arrived
                                // If not, the avatar completion block will composite both when it finishes
                                if (!user.rawProfileImage || user.rawProfileImage.size.width == 0) {
                                    return;
                                }
                                user.profileImage = [DCContentManager processedAvatarForUser:user context:DCAssetContextChat];
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [NSNotificationCenter.defaultCenter
                                        postNotificationName:@"RELOAD USER DATA"
                                                      object:user];
                                });
                            }];
    }
}

// Converts an NSDictionary created from json representing a role into a DCRole
// object Also keeps the role in DCServerCommunicator.loadedUsers if cache:YES
+ (DCRole *)convertJsonRole:(NSDictionary *)jsonRole cache:(bool)cache {
    // NSLog(@"%@", jsonUser);
    DCRole *newRole      = DCRole.new;
    newRole.snowflake    = [jsonRole objectForKey:@"id"];
    newRole.name         = [jsonRole objectForKey:@"name"];
    newRole.color        = [[jsonRole objectForKey:@"color"] intValue];
    newRole.hoist        = [[jsonRole objectForKey:@"hoist"] boolValue];
    newRole.iconID       = [jsonRole objectForKey:@"icon"];          // can be NSNull
    newRole.unicodeEmoji = [jsonRole objectForKey:@"unicode_emoji"]; // can be nil
    newRole.position     = [[jsonRole objectForKey:@"position"] intValue];
    newRole.permissions  = [jsonRole objectForKey:@"permissions"];
    newRole.managed      = [[jsonRole objectForKey:@"managed"] boolValue];
    newRole.mentionable  = [[jsonRole objectForKey:@"mentionable"] boolValue];

    // Save to DCServerCommunicator.loadedRoles
    if (cache) {
        [DCServerCommunicator.sharedInstance setRole:newRole forSnowflake:newRole.snowflake];
    }

    return newRole;
}

+ (void)getRoleIcon:(DCRole *)role {
    @autoreleasepool {
        role.icon = [UIImage new];

        if ((NSNull *)role.snowflake == [NSNull null] || (NSNull *)role.iconID == [NSNull null]) {
            return;
        }
        SDWebImageManager *manager = [SDWebImageManager sharedManager];
        NSURL *iconURL             = [NSURL URLWithString:[NSString
                                                  stringWithFormat:
                                                      @"https://cdn.discordapp.com/role-icons/%@/%@.png?size=80",
                                                      role.snowflake, role.iconID]];
        [manager downloadImageWithURL:iconURL
                              options:SDWebImageRetryFailed
                             progress:nil
                            completed:^(UIImage *retrievedImage, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                @autoreleasepool {
                                    if (!retrievedImage || !finished) {
                                        NSLog(@"Failed to download role icon with URL %@: %@", iconURL, error);
                                        return;
                                    }
                                    role.icon = retrievedImage;
                                    dispatch_async(
                                        dispatch_get_main_queue(),
                                        ^{
                                            [NSNotificationCenter
                                                    .defaultCenter
                                                postNotificationName:
                                                    @"RELOAD CHAT DATA"
                                                              object:nil];
                                        }
                                    );
                                }
                            }];
    }
}

+ (UILazyImage *)scaledImageFromImage:(UIImage *)image withURL:(NSURL *)url {
    if (!image) return nil;
    if (image.images.count > 1) {
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
    UILazyImage *newImage = [UILazyImage new];
    newImage.image = roundedCornerImage(UIGraphicsGetImageFromCurrentImageContext(), 6);
    UIGraphicsEndImageContext();
    newImage.imageURL = url;
    return newImage;
}

+ (DCEmoji *)convertJsonEmoji:(NSDictionary *)jsonEmoji cache:(BOOL)cache {
    if (cache && [DCServerCommunicator.sharedInstance emojiForSnowflake:[jsonEmoji objectForKey:@"id"]]) {
        // return pre-cached
        return [DCServerCommunicator.sharedInstance emojiForSnowflake:[jsonEmoji objectForKey:@"id"]];
    }

    DCEmoji *newEmoji  = DCEmoji.new;
    newEmoji.snowflake = [jsonEmoji objectForKey:@"id"];
    newEmoji.name      = [jsonEmoji objectForKey:@"name"];
    newEmoji.animated  = [[jsonEmoji objectForKey:@"animated"] boolValue];

    // Save to DCServerCommunicator.loadedEmojis
    if (cache) {
        [DCServerCommunicator.sharedInstance setEmoji:newEmoji forSnowflake:newEmoji.snowflake];
    }

    return newEmoji;
}

// Converts an NSDictionary created from json representing a message into a
// message object
+ (DCMessage *)convertJsonMessage:(NSDictionary *)jsonMessage {
    DCMessage *newMessage = DCMessage.new;
    @autoreleasepool {
        NSDictionary *author = [jsonMessage objectForKey:@"author"];
        NSString *authorId   = author ? [author objectForKey:@"id"] : nil;
        // NSLog(@"[Message] raw embeds: %@ raw attachments: %@", 
        //     [jsonMessage objectForKey:@"embeds"],
        //     [jsonMessage objectForKey:@"attachments"]);

        DCUser *authorUser = [DCServerCommunicator.sharedInstance userForSnowflake:authorId];
        if (!authorUser && authorId != nil && ![authorId isKindOfClass:[NSNull class]]) {
            authorUser = [DCTools convertJsonUser:[jsonMessage valueForKeyPath:@"author"] cache:YES];
        }

        // load referenced message if it exists
        float contentWidth = UIScreen.mainScreen.bounds.size.width - 63;

        NSDictionary *referencedJsonMessage =
            [jsonMessage objectForKey:@"referenced_message"];
        if ([[jsonMessage objectForKey:@"referenced_message"]
                isKindOfClass:[NSDictionary class]]) {
            DCMessage *referencedMessage = DCMessage.new;

            NSString *referencedAuthorId =
                [jsonMessage valueForKeyPath:@"referenced_message.author.id"];

            DCUser *referencedAuthor = [DCServerCommunicator.sharedInstance userForSnowflake:referencedAuthorId];
            if (!referencedAuthor && referencedAuthorId) {
                referencedAuthor = [DCTools convertJsonUser:[jsonMessage valueForKeyPath:@"referenced_message.author"] cache:YES];
            }

            referencedMessage.author = referencedAuthor;
            if ([[referencedJsonMessage objectForKey:@"content"]
                    isKindOfClass:[NSString class]]) {
                referencedMessage.content =
                    [referencedJsonMessage objectForKey:@"content"];
                if ([referencedMessage.content isEqualToString:@""]) {
                    referencedMessage.content = @"Click to view attachment";
                }
            } else {
                referencedMessage.content = @"";
            }
            referencedMessage.messageType     = [[referencedJsonMessage objectForKey:@"type"] intValue];
            referencedMessage.snowflake       = [referencedJsonMessage objectForKey:@"id"];
            CGSize authorNameSize             = [[referencedMessage.author 
                displayNameInGuild:DCServerCommunicator.sharedInstance.selectedChannel.parentGuild]
                     sizeWithFont:[UIFont boldSystemFontOfSize:10]
                constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                    lineBreakMode:(NSLineBreakMode)UILineBreakModeWordWrap];
            referencedMessage.authorNameWidth = 80 + authorNameSize.width;

            newMessage.referencedMessage = referencedMessage;
        }

        newMessage.author          = authorUser;
        newMessage.messageType     = [[jsonMessage objectForKey:@"type"] intValue];
        newMessage.content         = [jsonMessage objectForKey:@"content"];
        newMessage.snowflake       = [jsonMessage objectForKey:@"id"];
        newMessage.attachments     = NSMutableArray.new;
        newMessage.attachmentCount = 0;

        static dispatch_once_t dateFormatOnceToken;
        static NSDateFormatter *dateFormatter;
        dispatch_once(&dateFormatOnceToken, ^{
            dateFormatter = [NSDateFormatter new];
        });
        // Normalize timezone +HH:MM -> +HHMM for iOS 5 compatibility
        NSString *rawTimestamp = [jsonMessage objectForKey:@"timestamp"];
        if (rawTimestamp.length > 6) {
            NSString *tzPart = [rawTimestamp substringFromIndex:rawTimestamp.length - 6];
            if ([tzPart characterAtIndex:3] == ':') {
                rawTimestamp = [rawTimestamp stringByReplacingCharactersInRange:NSMakeRange(rawTimestamp.length - 3, 1) withString:@""];
            }
        }
        dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ";
        dateFormatter.locale     = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        newMessage.timestamp = [dateFormatter dateFromString:rawTimestamp];
        if (newMessage.timestamp == nil) {
            dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
            newMessage.timestamp = [dateFormatter dateFromString:rawTimestamp];
        }

        if ([jsonMessage objectForKey:@"edited_timestamp"] != [NSNull null]) {
            NSString *rawEditedTimestamp = [jsonMessage objectForKey:@"edited_timestamp"];
            if (rawEditedTimestamp.length > 6) {
                NSString *tzPart = [rawEditedTimestamp substringFromIndex:rawEditedTimestamp.length - 6];
                if ([tzPart characterAtIndex:3] == ':') {
                    rawEditedTimestamp = [rawEditedTimestamp stringByReplacingCharactersInRange:
                        NSMakeRange(rawEditedTimestamp.length - 3, 1) withString:@""];
                }
            }
            dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ";
            newMessage.editedTimestamp = [dateFormatter dateFromString:rawEditedTimestamp];
            if (newMessage.editedTimestamp == nil) {
                dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
                newMessage.editedTimestamp = [dateFormatter dateFromString:rawEditedTimestamp];
            }
        }

        static dispatch_once_t prettyFormatOnceToken;
        static NSDateFormatter *prettyDateFormatter;
        dispatch_once(&prettyFormatOnceToken, ^{
            prettyDateFormatter = [NSDateFormatter new];
        });
        prettyDateFormatter.dateStyle                  = NSDateFormatterShortStyle;
        prettyDateFormatter.timeStyle                  = NSDateFormatterShortStyle;
        prettyDateFormatter.doesRelativeDateFormatting = YES;

        newMessage.prettyTimestamp =
            [prettyDateFormatter stringFromDate:newMessage.timestamp];
        // Load embeded images from both links and attatchments
        // ─── EMBEDS ───────────────────────────────────────────────────────────────────
        // Discord embeds are rich previews generated server-side from links in messages.
        // Three types are handled: image (static image previews), gifv (Tenor/Giphy gifs),
        // and video (third party video links like YouTube, Instagram etc.)
        NSArray *embeds = [jsonMessage objectForKey:@"embeds"];
        if (embeds) {
            for (NSDictionary *embed in embeds) {
                NSString *embedType = [embed objectForKey:@"type"];
                // image embedding log
                // NSLog(@"[Embed] type: %@ url: %@", embedType, [embed objectForKey:@"url"]);
                // video embedding log
                // NSLog(@"[Embed] type: %@ url: %@ video_url: %@", 
                //     embedType, 
                //     [embed objectForKey:@"url"],
                //     [embed valueForKeyPath:@"video.url"]);
                // image/gifv
                // Handle static image embeds and Tenor/Giphy gif embeds.
                // gifv from other providers falls through to the video block below.
                if ([embedType isEqualToString:@"image"]
                    || (
                        [embedType isEqualToString:@"gifv"]
                        && ([[embed valueForKeyPath:@"provider.name"] isEqualToString:@"Tenor"]
                         || [[embed valueForKeyPath:@"provider.name"] isEqualToString:@"Giphy"])
                    )) {
                    newMessage.attachmentCount++;
                    newMessage.content = [newMessage.content stringByReplacingOccurrencesOfString:[embed objectForKey:@"url"] withString:@""];

                    NSString *attachmentURL;
                    // NSLog(@"[Embed] embedType: %@ proxy_url: %@ thumbnail_url: %@",
                    //     embedType,
                    //     [embed valueForKeyPath:@"thumbnail.proxy_url"],
                    //     [embed valueForKeyPath:@"thumbnail.url"]);
                    
                    // gifv URL construction
                    // Tenor and Giphy use different URL schemes to serve their gifs.
                    // Tenor: reconstruct the HD gif URL from the thumbnail path components.
                    // Giphy: swap .mp4 for .gif in the video URL.
                    // Regular image embeds: use thumbnail proxy_url or thumbnail url directly.
                    if ([embedType isEqualToString:@"gifv"]) {
                        if ([[embed valueForKeyPath:@"provider.name"] isEqualToString:@"Tenor"]) {
                            NSString *thumbnailURLString = [embed valueForKeyPath:@"thumbnail.url"];
                            NSArray *parts = [thumbnailURLString componentsSeparatedByString:@"/"];
                            // parts[0] = "https:", parts[1] = "", parts[2] = "media.tenor.com", parts[3] = gifId, parts[4] = filename
                            NSString *gifId = parts[3];
                            NSString *filename = [parts[4] stringByReplacingOccurrencesOfString:@".png" withString:@".gif"];
                            NSString *newGifId = [gifId stringByReplacingCharactersInRange:NSMakeRange(gifId.length - 1, 1) withString:@"C"]; // -AAAAC (0x00000002) = HD GIF
                            attachmentURL = [NSString stringWithFormat:@"https://media.tenor.com/%@/%@", newGifId, filename];
                            // NSLog(@"[Tenor] thumbnail.url: %@ constructed: %@", [embed valueForKeyPath:@"thumbnail.url"], attachmentURL);
                        } else if ([[embed valueForKeyPath:@"provider.name"] isEqualToString:@"Giphy"]) {
                            attachmentURL = [[embed valueForKeyPath:@"video.url"] stringByReplacingOccurrencesOfString:@".mp4" withString:@".gif"];
                        }
                    } else if ([embed valueForKeyPath:@"thumbnail.proxy_url"] != [NSNull null]) {
                        attachmentURL = [embed valueForKeyPath:@"thumbnail.proxy_url"];
                    } else if ([embed valueForKeyPath:@"thumbnail.url"] != [NSNull null]) {
                        attachmentURL = [embed valueForKeyPath:@"thumbnail.url"];
                    } else {
                        attachmentURL = [embed objectForKey:@"url"];
                    }

                    // isGif detection
                    // Detect gif content — either explicit gifv embed type or .gif file extension in URL.
                    // CDN-hosted gifs from Discord itself come through as type "image" with a .gif URL.
                    NSURL *embedNSURL = [NSURL URLWithString:[embed objectForKey:@"url"]];
                    NSString *pathExtension = [embedNSURL.path.lowercaseString pathExtension];
                    BOOL isGif = [embedType isEqualToString:@"gifv"] || [pathExtension isEqualToString:@"gif"];

                    NSInteger width     = [[embed valueForKeyPath:@"thumbnail.width"] integerValue];
                    NSInteger height    = [[embed valueForKeyPath:@"thumbnail.height"] integerValue];
                    CGFloat aspectRatio = (CGFloat)width / (CGFloat)height;

                    if (height > 1024) {
                        height = 1024;
                        width  = height * aspectRatio;
                        if (width > 1024) {
                            width  = 1024;
                            height = width / aspectRatio;
                        }
                    } else if (width > 1024) {
                        width  = 1024;
                        height = width / aspectRatio;
                        if (height > 1024) {
                            height = 1024;
                            width  = height * aspectRatio;
                        }
                    }

                    // Weed out webp images and request a png that iOS can present
                    // URL Construction
                    // Build the final download URL, requesting PNG format to ensure iOS compatibility.
                    // Some Discord CDN URLs already have width/height baked in — don't append them again.
                    // Always trim trailing & or ? before appending parameters to avoid malformed URLs.
                    // NSLog(@"[Embed Image] attachmentURL before construction: %@", attachmentURL);
                    BOOL alreadyHasDimensions = [attachmentURL rangeOfString:@"width="].location != NSNotFound;
                    NSURL *urlString;
                    if (alreadyHasDimensions) {
                        NSString *trimmedURL = [attachmentURL stringByTrimmingCharactersInSet:
                            [NSCharacterSet characterSetWithCharactersInString:@"&?"]];
                        urlString = [NSURL URLWithString:[NSString
                            stringWithFormat:@"%@%cformat=png", trimmedURL,
                            [trimmedURL rangeOfString:@"?"].location == NSNotFound ? '?' : '&']];
                        // NSLog(@"[Embed Image] final urlString: %@", urlString);
                    } else if (width != 0 || height != 0) {
                        NSString *trimmedURL = [attachmentURL stringByTrimmingCharactersInSet:
                            [NSCharacterSet characterSetWithCharactersInString:@"&?"]];
                        urlString = [NSURL URLWithString:[NSString
                            stringWithFormat:@"%@%cformat=png&width=%ld&height=%ld", trimmedURL,
                            [trimmedURL rangeOfString:@"?"].location == NSNotFound ? '?' : '&',
                            (long)width, (long)height]];
                        // NSLog(@"[Embed Image] final urlString: %@", urlString);
                    } else {
                        NSString *trimmedURL = [attachmentURL stringByTrimmingCharactersInSet:
                            [NSCharacterSet characterSetWithCharactersInString:@"&?"]];
                        urlString = [NSURL URLWithString:[NSString
                            stringWithFormat:@"%@%cformat=png", trimmedURL,
                            [trimmedURL rangeOfString:@"?"].location == NSNotFound ? '?' : '&']];
                        // NSLog(@"[Embed Image] final urlString: %@", urlString);
                    }

                    // GIF VS Static
                    // Gif attachments use DCGifInfo (data only, no UIKit) — the view is created later
                    // in cellForRowAtIndexPath on the main thread. Static images use UILazyImage directly.
                    NSUInteger idx = [newMessage.attachments count];
                    if (isGif) {
                        DCGifInfo *gif = [DCGifInfo new];
                        gif.gifURL = [NSURL URLWithString:attachmentURL];
                        if ([[embed valueForKeyPath:@"thumbnail.placeholder_version"] integerValue] == 1) {
                            UIImage *img = thumbHashToImage([NSData dataWithBase64EncodedString:[embed valueForKeyPath:@"thumbnail.placeholder"]]);
                            UIImage *scaled = [DCTools scaledImageFromImage:img withURL:urlString].image;
                            gif.staticThumbnail = scaled;
                        }
                        [newMessage.attachments addObject:gif];

                        if (!DCServerCommunicator.sharedInstance.dataSaver) {
                            SDWebImageManager *manager = [SDWebImageManager sharedManager];
                            [manager downloadImageWithURL:urlString
                                                  options:SDWebImageCacheMemoryOnly | SDWebImageRetryFailed
                                                 progress:nil
                                                completed:^(UIImage *retrievedImage, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                                    @autoreleasepool {
                                                        if (!retrievedImage || !finished) {
                                                            NSLog(@"Failed to load gif thumbnail with URL %@: %@", urlString, error);
                                                            return;
                                                        }
                                                        UIImage *firstFrame = (retrievedImage.images.count > 0) ? retrievedImage.images[0] : retrievedImage;
                                                        UIImage *scaled = [DCTools scaledImageFromImage:firstFrame withURL:nil].image;
                                                        dispatch_async(dispatch_get_main_queue(), ^{
                                                            gif.staticThumbnail    = scaled;
                                                            [newMessage.attachments replaceObjectAtIndex:idx withObject:gif];
                                                            [NSNotificationCenter.defaultCenter
                                                                postNotificationName:@"RELOAD CHAT DATA"
                                                                              object:newMessage];
                                                        });
                                                    }
                                                }];
                        }
                    } else {
                        if ([[embed valueForKeyPath:@"thumbnail.placeholder_version"] integerValue] == 1) {
                            UIImage *img = thumbHashToImage([NSData dataWithBase64EncodedString:[embed valueForKeyPath:@"thumbnail.placeholder"]]);
                            [newMessage.attachments addObject:[DCTools scaledImageFromImage:img withURL:urlString]];
                        } else {
                            [newMessage.attachments addObject:@[ @(width), @(height) ]];
                        }

                        if (!DCServerCommunicator.sharedInstance.dataSaver) {
                            SDWebImageManager *manager = [SDWebImageManager sharedManager];
                            [manager downloadImageWithURL:urlString
                                                  options:SDWebImageCacheMemoryOnly | SDWebImageRetryFailed
                                                 progress:nil
                                                completed:^(UIImage *retrievedImage, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                                    @autoreleasepool {
                                                        if (!retrievedImage || !finished) {
                                                            NSLog(@"Failed to load embed image with URL %@: %@", urlString, error);
                                                            return;
                                                        }
                                                        dispatch_async(dispatch_get_main_queue(), ^{
                                                            [newMessage.attachments replaceObjectAtIndex:idx withObject:[DCTools scaledImageFromImage:retrievedImage withURL:urlString]];
                                                            [NSNotificationCenter.defaultCenter
                                                                postNotificationName:@"RELOAD MESSAGE DATA"
                                                                              object:newMessage];
                                                        });
                                                    }
                                                }];
                        }
                    }
                } else if ([embedType isEqualToString:@"video"] ||
                           [embedType isEqualToString:@"gifv"]) {
                    // Video Embed
                    // Handle video embeds — YouTube, Instagram, third party video links etc.
                    // Also catches gifv embeds that aren't from Tenor or Giphy (handled above).
                    // videoURL = the actual playable video URL passed to MPMoviePlayerViewController.
                    // baseURL = the thumbnail image URL for the cell preview.
                    NSString *originalEmbedURL = [embed objectForKey:@"url"]; // NEW — captures the URL once for reuse

                        BOOL isYouTube = originalEmbedURL &&
                                         ([originalEmbedURL hasPrefix:@"https://www.youtube.com"] ||
                                          [originalEmbedURL hasPrefix:@"https://m.youtube.com"]   ||
                                          [originalEmbedURL hasPrefix:@"https://youtube.com"]     ||
                                          [originalEmbedURL hasPrefix:@"https://youtu.be"]);

                        NSURL *attachmentURL;

                    if (!isYouTube) {
                        newMessage.content = [newMessage.content stringByReplacingOccurrencesOfString:originalEmbedURL withString:@""];
                    }
                    // NSLog(@"[Video Embed] full embed: %@", embed);
                    if ([embed valueForKeyPath:@"video.proxy_url"] != nil &&
                        [[embed valueForKeyPath:@"video.proxy_url"]
                            isKindOfClass:[NSString class]]) {
                        attachmentURL = [NSURL URLWithString:[embed valueForKeyPath:@"video.proxy_url"]];
                    } else if ([embed valueForKeyPath:@"video.url"] != nil &&
                               [[embed valueForKeyPath:@"video.url"] isKindOfClass:[NSString class]]) {
                        attachmentURL = [NSURL URLWithString:[embed valueForKeyPath:@"video.url"]];
                    } else {
                        attachmentURL = [NSURL URLWithString:originalEmbedURL];
                    }

                    //[newMessage.attachments
                    // addObject:[[MPMoviePlayerViewController alloc]
                    // initWithContentURL:attachmentURL]];
                    DCChatVideoAttachment *video = [[[NSBundle mainBundle]
                        loadNibNamed:@"DCChatVideoAttachment"
                               owner:self
                             options:nil] objectAtIndex:0];

                    video.videoURL = attachmentURL;
                    // YouTube videos and shorts
                    if (isYouTube && originalEmbedURL) {
                        NSURL *ytURL = [NSURL URLWithString:originalEmbedURL];
                        NSString *finalURLString = originalEmbedURL;
                        NSArray *pathComponents = ytURL.pathComponents;
                        NSUInteger shortsIdx = [pathComponents indexOfObject:@"shorts"];
                        if (shortsIdx != NSNotFound && shortsIdx + 1 < pathComponents.count) {
                            NSString *videoID = pathComponents[shortsIdx + 1];
                            finalURLString = [NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@", videoID];
                        }
                        video.linkURL = [NSURL URLWithString:finalURLString];
                    }

                    // baseURL resolution
                    // Resolve the best available thumbnail URL in priority order:
                    // 1. thumbnail.proxy_url (Discord CDN proxy — most reliable)
                    // 2. thumbnail.url (original source thumbnail)
                    // 3. video.proxy_url (Discord's external image proxy for third party sites)
                    // Falls back to the embed URL itself if none are available.
                    NSString *baseURL = [embed objectForKey:@"url"];

                    if ([embed valueForKeyPath:@"thumbnail.proxy_url"] != nil &&
                        [[embed valueForKeyPath:@"thumbnail.proxy_url"] isKindOfClass:[NSString class]]) {
                        baseURL = [embed valueForKeyPath:@"thumbnail.proxy_url"];
                    } else if ([embed valueForKeyPath:@"thumbnail.url"] != nil &&
                               [[embed valueForKeyPath:@"thumbnail.url"] isKindOfClass:[NSString class]]) {
                        baseURL = [embed valueForKeyPath:@"thumbnail.url"];
                    } else if ([embed valueForKeyPath:@"video.proxy_url"] != nil &&
                               [[embed valueForKeyPath:@"video.proxy_url"] isKindOfClass:[NSString class]]) {
                        baseURL = [embed valueForKeyPath:@"video.proxy_url"];
                    }

                    NSInteger width =
                        [[embed valueForKeyPath:@"video.width"] integerValue];
                    NSInteger height =
                        [[embed valueForKeyPath:@"video.height"] integerValue];
                    CGFloat aspectRatio = (CGFloat)width / (CGFloat)height;

                    if (height > 1024) {
                        height = 1024;
                        width  = height * aspectRatio;
                        if (width > 1024) {
                            width  = 1024;
                            height = width / aspectRatio;
                        }
                    } else if (width > 1024) {
                        width  = 1024;
                        height = width / aspectRatio;
                        if (height > 1024) {
                            height = 1024;
                            width  = height * aspectRatio;
                        }
                    }

                    // Discord CDN format=png
                    // Only append format=png for Discord CDN URLs — third party URLs don't support it
                    // and appending it causes SSL errors or invalid responses on iOS 5/6.
                    NSURL *urlString = [NSURL URLWithString:baseURL];
                    BOOL isDiscord = [baseURL hasPrefix:@"https://media.discordapp.net/"] ||
                                     [baseURL hasPrefix:@"https://images-ext-1.discordapp.net/"] ||
                                     [baseURL hasPrefix:@"https://images-ext-2.discordapp.net/"];

                    if (isDiscord) {
                        if (width != 0 || height != 0) {
                            urlString = [NSURL URLWithString:[NSString stringWithFormat:
                                @"%@%cformat=png&width=%ld&height=%ld",
                                urlString,
                                [urlString query].length == 0 ? '?' : '&',
                                (long)width, (long)height]];
                        } else {
                            urlString = [NSURL URLWithString:[NSString stringWithFormat:
                                @"%@%cformat=png",
                                urlString,
                                [urlString query].length == 0 ? '?' : '&']];
                        }
                    }
                    // non-Discord URLs used as-is, no format parameter appended

                    // Placeholder/Thumbhash
                    // Show a blurry thumbhash placeholder immediately while the real thumbnail downloads.
                    // Check both thumbnail and video fields since third party embeds store it under video.
                    NSUInteger idx = [newMessage.attachments count];
                    if ([[embed valueForKeyPath:@"thumbnail.placeholder_version"] integerValue] == 1) {
                        UIImage *img = thumbHashToImage([NSData dataWithBase64EncodedString:[embed valueForKeyPath:@"thumbnail.placeholder"]]);
                        video.thumbnail.image = [DCTools scaledImageFromImage:img withURL:urlString].image;
                        [newMessage.attachments addObject:video];
                    } else if ([[embed valueForKeyPath:@"video.placeholder_version"] integerValue] == 1) {
                        UIImage *img = thumbHashToImage([NSData dataWithBase64EncodedString:[embed valueForKeyPath:@"video.placeholder"]]);
                        video.thumbnail.image = [DCTools scaledImageFromImage:img withURL:urlString].image;
                        [newMessage.attachments addObject:video];
                    } else {
                        [newMessage.attachments addObject:@[ @(width), @(height) ]];
                    }

                    if (!DCServerCommunicator.sharedInstance.dataSaver) {
                        SDWebImageManager *manager = [SDWebImageManager sharedManager];
                        [manager downloadImageWithURL:urlString
                                              options:SDWebImageCacheMemoryOnly | SDWebImageRetryFailed
                                             progress:nil
                                            completed:^(UIImage *retrievedImage, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                                @autoreleasepool {
                                                    if (!retrievedImage || !finished) {
                                                        NSLog(@"Failed to load video thumbnail with URL %@: %@", urlString, error);
                                                        dispatch_async(dispatch_get_main_queue(), ^{
                                                            video.videoWarning.hidden = NO;
                                                            video.videoWarning.text = @"Unsupported Embed";
                                                            [newMessage.attachments replaceObjectAtIndex:idx withObject:video];
                                                            [NSNotificationCenter.defaultCenter
                                                                postNotificationName:@"RELOAD CHAT DATA"
                                                                              object:newMessage];
                                                        });
                                                        return;
                                                    }
                                                    dispatch_async(
                                                        dispatch_get_main_queue(),
                                                        ^{
                                                            UIImage *firstFrame = (retrievedImage.images.count > 0) ? retrievedImage.images[0] : retrievedImage;
                                                            UIImage *scaled = [DCTools scaledImageFromImage:firstFrame withURL:nil].image;
                                                            video.thumbnail.image = roundedCornerImage(scaled, 6);
                                                            [newMessage.attachments replaceObjectAtIndex:idx withObject:video];
                                                            [NSNotificationCenter.defaultCenter
                                                                postNotificationName:@"RELOAD CHAT DATA"
                                                                              object:newMessage];
                                                        }
                                                    );
                                                }
                                            }];
                    }

                    video.userInteractionEnabled = YES;
                    newMessage.attachmentCount++;
                } else {
                    // NSLog(@"unknown embed type %@", embedType);
                    continue;
                }
            }
        }

        // ─── DIRECT ATTACHMENTS ───────────────────────────────────────────────────────
        // Files directly uploaded by users — images, videos, audio etc.
        // Unlike embeds these come from Discord's CDN directly and have explicit content_type.
        NSArray *attachments = [jsonMessage objectForKey:@"attachments"];
        if (attachments) {
            for (NSDictionary *attachment in attachments) {
                NSString *fileType = [attachment objectForKey:@"content_type"];
                // Image Attachments
                // Image attachments — includes PNG, JPG, WebP, and GIF.
                // WebP files need format=png appended so iOS can decode them.
                // GIF files are routed to DCGifInfo for tap-to-play behavior.
                if ([fileType rangeOfString:@"image/"].location != NSNotFound) {
                    newMessage.attachmentCount++;

                    NSString *attachmentURL;
                    if ([attachment objectForKey:@"proxy_url"]) {
                        attachmentURL = [attachment objectForKey:@"proxy_url"];
                    } else {
                        attachmentURL = [attachment objectForKey:@"url"];
                    }
                    NSURL *attachmentNSURL = [NSURL URLWithString:attachmentURL];
                    NSString *pathExtension = [attachmentNSURL.path.lowercaseString pathExtension];
                    BOOL isGif = [fileType isEqualToString:@"image/gif"] || 
                                 [pathExtension isEqualToString:@"gif"];

                    NSInteger width     = [[attachment objectForKey:@"width"] integerValue];
                    NSInteger height    = [[attachment objectForKey:@"height"] integerValue];
                    CGFloat aspectRatio = (CGFloat)width / (CGFloat)height;

                    if (height > 1024) {
                        height = 1024;
                        width  = height * aspectRatio;
                        if (width > 1024) {
                            width  = 1024;
                            height = width / aspectRatio;
                        }
                    } else if (width > 1024) {
                        width  = 1024;
                        height = width / aspectRatio;
                        if (height > 1024) {
                            height = 1024;
                            width  = height * aspectRatio;
                        }
                    }

                    // Attachment URL Construction
                    // Weed out webp images and request a png that iOS can present
                    // Build download URL — same logic as image embeds.
                    // proxy_url already has dimensions baked in for some attachments, avoid doubling them.
                    // Always request format=png to handle WebP content that iOS can't decode natively.
                    BOOL alreadyHasDimensions = [attachmentURL rangeOfString:@"width="].location != NSNotFound;
                    NSURL *urlString;
                    if (alreadyHasDimensions) {
                        NSString *trimmedURL = [attachmentURL stringByTrimmingCharactersInSet:
                            [NSCharacterSet characterSetWithCharactersInString:@"&?"]];
                        urlString = [NSURL URLWithString:[NSString
                            stringWithFormat:@"%@%cformat=png", trimmedURL,
                            [trimmedURL rangeOfString:@"?"].location == NSNotFound ? '?' : '&']];
                        // NSLog(@"[Embed Image] urlString: %@", urlString);
                    } else {
                        NSString *trimmedURL = [attachmentURL stringByTrimmingCharactersInSet:
                            [NSCharacterSet characterSetWithCharactersInString:@"&?"]];
                        urlString = [NSURL URLWithString:[NSString
                            stringWithFormat:@"%@%cformat=png&width=%ld&height=%ld", trimmedURL,
                            [trimmedURL rangeOfString:@"?"].location == NSNotFound ? '?' : '&',
                            (long)width, (long)height]];
                        // NSLog(@"[Embed Image] urlString: %@", urlString);
                    }

                    NSUInteger idx = [newMessage.attachments count];

                    if (isGif) {
                        DCGifInfo *gif = [DCGifInfo new];
                        gif.gifURL = urlString;
                        if ([[attachment objectForKey:@"placeholder_version"] integerValue] == 1) {
                            UIImage *img = thumbHashToImage([NSData dataWithBase64EncodedString:[attachment objectForKey:@"placeholder"]]);
                            UIImage *scaled = [DCTools scaledImageFromImage:img withURL:urlString].image;
                            gif.staticThumbnail    = scaled;
                        }
                        [newMessage.attachments addObject:gif];

                        if (!DCServerCommunicator.sharedInstance.dataSaver) {
                            SDWebImageManager *manager = [SDWebImageManager sharedManager];
                            [manager downloadImageWithURL:urlString
                                                  options:SDWebImageCacheMemoryOnly | SDWebImageRetryFailed
                                                 progress:nil
                                                completed:^(UIImage *retrievedImage, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                                    @autoreleasepool {
                                                        if (!retrievedImage || !finished) {
                                                            NSLog(@"Failed to load gif with URL %@: %@", urlString, error);
                                                            return;
                                                        }
                                                        // Take only the first frame for the static thumbnail
                                                        UIImage *firstFrame = (retrievedImage.images.count > 0)
                                                            ? retrievedImage.images[0]
                                                            : retrievedImage;
                                                        UIImage *scaled = [DCTools scaledImageFromImage:firstFrame withURL:nil].image;
                                                        dispatch_async(dispatch_get_main_queue(), ^{
                                                            gif.staticThumbnail    = scaled;
                                                            [newMessage.attachments replaceObjectAtIndex:idx withObject:gif];
                                                            [NSNotificationCenter.defaultCenter
                                                                postNotificationName:@"RELOAD CHAT DATA"
                                                                              object:newMessage];
                                                        });
                                                    }
                                                }];
                        }
                    } else {
                        if ([[attachment objectForKey:@"placeholder_version"] integerValue] == 1) {
                            UIImage *img = thumbHashToImage([NSData dataWithBase64EncodedString:[attachment objectForKey:@"placeholder"]]);
                            [newMessage.attachments addObject:[DCTools scaledImageFromImage:img withURL:urlString]];
                        } else {
                            [newMessage.attachments addObject:@[ @(width), @(height) ]];
                        }

                        if (!DCServerCommunicator.sharedInstance.dataSaver) {
                            SDWebImageManager *manager = [SDWebImageManager sharedManager];
                            [manager downloadImageWithURL:urlString
                                                  options:SDWebImageCacheMemoryOnly | SDWebImageRetryFailed
                                                 progress:nil
                                                completed:^(UIImage *retrievedImage, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                                    @autoreleasepool {
                                                        if (!retrievedImage || !finished) {
                                                            NSLog(@"Failed to load image with URL %@: %@", urlString, error);
                                                            return;
                                                        }
                                                        dispatch_async(dispatch_get_main_queue(), ^{
                                                            [newMessage.attachments replaceObjectAtIndex:idx withObject:[DCTools scaledImageFromImage:retrievedImage withURL:urlString]];
                                                            [NSNotificationCenter.defaultCenter
                                                                postNotificationName:@"RELOAD MESSAGE DATA"
                                                                              object:newMessage];
                                                        });
                                                    }
                                                }];
                        }
                    }

                // Video Attachments
                // Directly uploaded video files — only formats natively supported by iOS MPMoviePlayer.
                // Other video formats (webm, avi etc.) fall through to the unknown handler below
                // which appends the raw URL to the message content as a fallback.
                } else if ([fileType rangeOfString:@"video/quicktime"].location != NSNotFound ||
                           [fileType rangeOfString:@"video/mp4"].location != NSNotFound ||
                           [fileType rangeOfString:@"video/mpv"].location != NSNotFound ||
                           [fileType rangeOfString:@"video/3gpp"].location != NSNotFound) {
                    // iOS only supports these video formats
                    newMessage.attachmentCount++;

                    NSURL *attachmentURL =
                        [NSURL URLWithString:[attachment objectForKey:@"url"]];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        //[newMessage.attachments
                        // addObject:[[MPMoviePlayerViewController alloc]
                        // initWithContentURL:attachmentURL]];
                        DCChatVideoAttachment *video = [[NSBundle mainBundle]
                                                           loadNibNamed:@"DCChatVideoAttachment"
                                                                  owner:self
                                                                options:nil]
                                                           .firstObject;

                        video.videoURL = attachmentURL;

                        NSString *baseURL = [attachment objectForKey:@"proxy_url"];

                        NSInteger width =
                            [[attachment objectForKey:@"width"] integerValue];
                        NSInteger height =
                            [[attachment objectForKey:@"height"] integerValue];
                        CGFloat aspectRatio = (CGFloat)width / (CGFloat)height;

                        if (height > 1024) {
                            height = 1024;
                            width  = height * aspectRatio;
                            if (width > 1024) {
                                width  = 1024;
                                height = width / aspectRatio;
                            }
                        } else if (width > 1024) {
                            width  = 1024;
                            height = width / aspectRatio;
                            if (height > 1024) {
                                height = 1024;
                                width  = height * aspectRatio;
                            }
                        }


                        NSURL *urlString = [NSURL
                            URLWithString:[NSString
                                              stringWithFormat:@"%@format=png&width=%ld&height=%ld",
                                                               baseURL, (long)width, (long)height]];
                        if ([urlString query].length == 0) {
                            urlString = [NSURL URLWithString:[NSString stringWithFormat:
                                                                           @"%@?format=png&width=%ld&height=%ld",
                                                                           baseURL, (long)width, (long)height]];
                        }

                        NSUInteger idx = [newMessage.attachments count];
                        if ([[attachment objectForKey:@"placeholder_version"] integerValue] == 1) {
                            UIImage *img          = thumbHashToImage([NSData dataWithBase64EncodedString:[attachment objectForKey:@"placeholder"]]);
                            video.thumbnail.image = [DCTools scaledImageFromImage:img withURL:urlString].image;
                            [newMessage.attachments addObject:video];
                        } else {
                            [newMessage.attachments addObject:@[ @(width), @(height) ]];
                        }

                        if (!DCServerCommunicator.sharedInstance.dataSaver) {
                            SDWebImageManager *manager = [SDWebImageManager sharedManager];
                            [manager downloadImageWithURL:urlString
                                                  options:SDWebImageCacheMemoryOnly | SDWebImageRetryFailed
                                                 progress:nil
                                                completed:^(UIImage *retrievedImage, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                                    @autoreleasepool {
                                                        if (!retrievedImage || !finished
                                                            || !video || !video.thumbnail
                                                            || ![video.thumbnail isKindOfClass:[UIImageView class]]) {
                                                            NSLog(@"Failed to load video thumbnail with URL %@: %@", imageURL, error);
                                                            dispatch_async(dispatch_get_main_queue(), ^{
                                                                video.videoWarning.hidden = NO;
                                                                video.videoWarning.text = @"Unsupported Attachment";
                                                                [newMessage.attachments replaceObjectAtIndex:idx withObject:video];
                                                                [NSNotificationCenter.defaultCenter
                                                                    postNotificationName:@"RELOAD CHAT DATA"
                                                                                  object:newMessage];
                                                            });
                                                            return;
                                                        }
                                                        dispatch_async(
                                                            dispatch_get_main_queue(),
                                                            ^{
                                                                video.thumbnail.image =
                                                                    [DCTools scaledImageFromImage:retrievedImage
                                                                                          withURL:nil]
                                                                        .image;
                                                                [newMessage.attachments replaceObjectAtIndex:idx withObject:video];
                                                                [NSNotificationCenter.defaultCenter
                                                                    postNotificationName:@"RELOAD MESSAGE DATA"
                                                                                  object:newMessage];
                                                            }
                                                        );
                                                    }
                                                }];
                        }
                        video.userInteractionEnabled = YES;
                    });
                } else {
                    // NSLog(@"unknown attachment type %@", fileType);
                    newMessage.content =
                        [NSString stringWithFormat:@"%@\n%@", newMessage.content,
                                                   [attachment objectForKey:@"url"]];
                    continue;
                }
            }
        }
        // sticker_items is a flat array — each entry has "id", "name", "format_type"
        // format_type: 1=PNG, 2=APNG, 3=Lottie JSON, 4=GIF
        NSArray *stickerItems = [jsonMessage objectForKey:@"sticker_items"];
        if (stickerItems && [stickerItems isKindOfClass:[NSArray class]] && stickerItems.count > 0) {
            for (NSDictionary *sticker in stickerItems) {
                if (![sticker isKindOfClass:[NSDictionary class]]) continue;

                NSString *stickerId   = [sticker objectForKey:@"id"];
                NSString *stickerName = [sticker objectForKey:@"name"];
                int formatType        = [[sticker objectForKey:@"format_type"] intValue];

                if (!stickerId || [stickerId isKindOfClass:[NSNull class]]) continue;

                // Format 3 = Lottie JSON — no renderer on iOS 5/6.
                if (formatType == 3) {
                    NSString *fallback = [NSString stringWithFormat:@"[sticker: %@]",
                                          ([stickerName isKindOfClass:[NSString class]] ? stickerName : @"unknown")];
                    newMessage.content = newMessage.content.length > 0
                        ? [newMessage.content stringByAppendingFormat:@" %@", fallback]
                        : fallback;
                    continue;
                }

                // Format 1 = PNG, Format 2 = APNG (media.discordapp.net transcodes to GIF),
                // Format 4 = GIF.
                NSString *extension = (formatType == 1) ? @"png" : @"gif";

                NSURL *stickerURL = [NSURL URLWithString:[NSString stringWithFormat:
                    @"https://media.discordapp.net/stickers/%@.%@?size=320",
                    stickerId, extension]];

                newMessage.isSticker = YES;
                newMessage.attachmentCount++;

                // Insert a square placeholder so heightForRowAtIndexPath can
                // return the correct row height before the image arrives.
                NSUInteger idx = newMessage.attachments.count;
                [newMessage.attachments addObject:@[@(160), @(160)]];

                SDWebImageManager *manager = [SDWebImageManager sharedManager];
                [manager downloadImageWithURL:stickerURL
                                      options:SDWebImageCacheMemoryOnly | SDWebImageRetryFailed
                                     progress:nil
                                    completed:^(UIImage *retrievedImage, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                        @autoreleasepool {
                                            if (!retrievedImage || !finished) {
                                                NSLog(@"Failed to load sticker %@ with URL %@: %@",
                                                      stickerId, stickerURL, error);
                                                // Zero out the placeholder so the height calc skips it,
                                                // then fall back to a text representation.
                                                NSString *fallback = [NSString stringWithFormat:@"[sticker: %@]",
                                                    ([stickerName isKindOfClass:[NSString class]] ? stickerName : @"unknown")];
                                                dispatch_async(dispatch_get_main_queue(), ^{
                                                    [newMessage.attachments replaceObjectAtIndex:idx withObject:@[@0, @0]];
                                                    newMessage.attachmentCount--;
                                                    newMessage.content = newMessage.content.length > 0
                                                        ? [newMessage.content stringByAppendingFormat:@" %@", fallback]
                                                        : fallback;
                                                    [NSNotificationCenter.defaultCenter
                                                        postNotificationName:@"RELOAD MESSAGE DATA"
                                                                      object:newMessage];
                                                });
                                                return;
                                            }

                                            // Wrap in UILazyImage so the existing attachment
                                            // rendering pipeline in DCChatViewController can
                                            // display it. DCChatStickerCell also reads this.
                                            UILazyImage *lazyImage = [UILazyImage new];
                                            lazyImage.image        = retrievedImage;
                                            lazyImage.imageURL     = stickerURL;
                                            dispatch_async(dispatch_get_main_queue(), ^{
                                                [newMessage.attachments replaceObjectAtIndex:idx withObject:lazyImage];
                                                [NSNotificationCenter.defaultCenter
                                                    postNotificationName:@"RELOAD MESSAGE DATA"
                                                                  object:newMessage];
                                            });
                                        }
                                    }];
            }
        }

        // Parse in-text mentions into readable @<username>
        NSArray *mentions     = [jsonMessage objectForKey:@"mentions"];
        NSArray *mentionRoles = [jsonMessage objectForKey:@"mention_roles"];

        if ([[jsonMessage objectForKey:@"mention_everyone"] boolValue]) {
            newMessage.pingingUser = true;
        }

        if (mentions.count || mentionRoles.count) {
            for (NSDictionary *mention in mentions) {
                if ([[mention objectForKey:@"id"] isEqualToString:
                                                      DCServerCommunicator.sharedInstance.snowflake]) {
                    newMessage.pingingUser = true;
                }
                if (![DCServerCommunicator.sharedInstance userForSnowflake:[mention objectForKey:@"id"]]) {
                    (void)[DCTools convertJsonUser:mention cache:true];
                }
            }

            static dispatch_once_t onceToken;
            static NSRegularExpression *regex;
            dispatch_once(&onceToken, ^{
                regex = [NSRegularExpression
                    regularExpressionWithPattern:@"\\<@(.*?)\\>"
                                         options:NSRegularExpressionCaseInsensitive
                                           error:NULL];
            });

            NSTextCheckingResult *embeddedMention = [regex
                firstMatchInString:newMessage.content
                           options:0
                             range:NSMakeRange(0, newMessage.content.length)];

            while (embeddedMention) {
                NSCharacterSet *charactersToRemove =
                    [NSCharacterSet.alphanumericCharacterSet invertedSet];
                NSString *mentionSnowflake =
                    [[[newMessage.content substringWithRange:embeddedMention.range]
                        componentsSeparatedByCharactersInSet:charactersToRemove]
                        componentsJoinedByString:@""];

                DCUser *user = [DCServerCommunicator.sharedInstance userForSnowflake:mentionSnowflake];

                DCRole *role = [DCServerCommunicator.sharedInstance roleForSnowflake:mentionSnowflake];

                for (DCGuild *guild in DCServerCommunicator.sharedInstance.guilds) {
                    if ([guild.userRoles containsObject:mentionSnowflake]) {
                        newMessage.pingingUser = true;
                    }
                }

                if ([mentionSnowflake
                        isEqualToString:DCServerCommunicator.sharedInstance
                                            .snowflake]) {
                    newMessage.pingingUser = true;
                } else if ([DCServerCommunicator.sharedInstance.selectedGuild
                                   .userRoles containsObject:mentionSnowflake]) {
                    newMessage.pingingUser = true;
                }

                NSString *mentionName = @"@MENTION";

                if (user) {
                    mentionName = [NSString stringWithFormat:@"@%@", user.username];
                } else if (role) {
                    mentionName = [NSString stringWithFormat:@"@%@", role.name];
                }

                newMessage.content = [newMessage.content
                    stringByReplacingCharactersInRange:embeddedMention.range
                                            withString:mentionName];

                embeddedMention = [regex
                    firstMatchInString:newMessage.content
                               options:0
                                 range:NSMakeRange(0, newMessage.content.length)];
            }
        }

        {
            // channels
            static dispatch_once_t onceToken;
            static NSRegularExpression *regex;
            dispatch_once(&onceToken, ^{
                regex = [NSRegularExpression
                    regularExpressionWithPattern:@"\\<#(.*?)\\>"
                                         options:NSRegularExpressionCaseInsensitive
                                           error:NULL];
            });

            NSTextCheckingResult *embeddedMention = [regex
                firstMatchInString:newMessage.content
                           options:0
                             range:NSMakeRange(0, newMessage.content.length)];
            while (embeddedMention) {
                NSCharacterSet *charactersToRemove =
                    [NSCharacterSet.alphanumericCharacterSet invertedSet];
                NSString *channelSnowflake =
                    [[[newMessage.content substringWithRange:embeddedMention.range]
                        componentsSeparatedByCharactersInSet:charactersToRemove]
                        componentsJoinedByString:@""];

                NSString *mentionName = @"#CHANNEL";
                DCChannel *channel    = [DCServerCommunicator.sharedInstance.channels objectForKey:channelSnowflake];
                if (channel) {
                    mentionName = [NSString stringWithFormat:@"#%@", channel.name];
                }

                newMessage.content = [newMessage.content
                    stringByReplacingCharactersInRange:embeddedMention.range
                                            withString:mentionName];

                embeddedMention = [regex
                    firstMatchInString:newMessage.content
                               options:0
                                 range:NSMakeRange(0, newMessage.content.length)];
            }
        }

        {
            // <t:timestamp:format>
            static dispatch_once_t onceToken;
            static NSRegularExpression *regex;
            dispatch_once(&onceToken, ^{
                regex = [NSRegularExpression
                    regularExpressionWithPattern:@"\\<t:(\\d+)(?::(\\w+))?\\>"
                                         options:NSRegularExpressionCaseInsensitive
                                           error:NULL];
            });
            NSTextCheckingResult *embeddedMention = [regex
                firstMatchInString:newMessage.content
                           options:0
                             range:NSMakeRange(0, newMessage.content.length)];
            while (embeddedMention) {
                NSRange timestampRange = [embeddedMention rangeAtIndex:1];
                if (timestampRange.location == NSNotFound || 
                    timestampRange.location + timestampRange.length > newMessage.content.length) {
                    break;
                }
                NSString *timestamp = [newMessage.content substringWithRange:timestampRange];
                
                // Format is optional — default to "f" if not present
                NSString *format = nil;
                NSRange formatRange = [embeddedMention rangeAtIndex:2];
                if (formatRange.location != NSNotFound && 
                    formatRange.location + formatRange.length <= newMessage.content.length) {
                    format = [newMessage.content substringWithRange:formatRange];
                }
                
                NSDate *date          = [NSDate dateWithTimeIntervalSince1970:[timestamp longLongValue]];
                NSString *replacement = @"TIME";
                if (date) {
                    prettyDateFormatter.doesRelativeDateFormatting = NO;
                    if (!format || [format isEqualToString:@"f"]) {
                        prettyDateFormatter.dateStyle = NSDateFormatterShortStyle;
                        prettyDateFormatter.timeStyle = NSDateFormatterFullStyle;
                    } else if (format && [format isEqualToString:@"F"]) {
                        prettyDateFormatter.dateStyle = NSDateFormatterFullStyle;
                        prettyDateFormatter.timeStyle = NSDateFormatterFullStyle;
                    } else if (format && [format isEqualToString:@"R"]) {
                        prettyDateFormatter.dateStyle                  = NSDateFormatterShortStyle;
                        prettyDateFormatter.timeStyle                  = NSDateFormatterShortStyle;
                        prettyDateFormatter.doesRelativeDateFormatting = YES;
                    } else if (format && [format isEqualToString:@"D"]) {
                        prettyDateFormatter.dateStyle = NSDateFormatterMediumStyle;
                        prettyDateFormatter.timeStyle = NSDateFormatterNoStyle;
                    } else if (format && [format isEqualToString:@"d"]) {
                        prettyDateFormatter.dateStyle = NSDateFormatterShortStyle;
                        prettyDateFormatter.timeStyle = NSDateFormatterNoStyle;
                    } else if (format && [format isEqualToString:@"t"]) {
                        prettyDateFormatter.dateStyle = NSDateFormatterNoStyle;
                        prettyDateFormatter.timeStyle = NSDateFormatterShortStyle;
                    } else if (format && [format isEqualToString:@"T"]) {
                        prettyDateFormatter.dateStyle = NSDateFormatterNoStyle;
                        prettyDateFormatter.timeStyle = NSDateFormatterMediumStyle;
                    }
                    replacement = [prettyDateFormatter stringFromDate:date];
                }
                newMessage.content = [newMessage.content stringByReplacingCharactersInRange:embeddedMention.range withString:replacement];
                embeddedMention    = [regex firstMatchInString:newMessage.content options:0 range:NSMakeRange(0, newMessage.content.length)];
            }
        }

        NSString *content = [newMessage.content emojizedString];

        content = [content stringByReplacingOccurrencesOfString:@"\u2122\uFE0F"
                                                     withString:@"™"];
        content = [content stringByReplacingOccurrencesOfString:@"\u00AE\uFE0F"
                                                     withString:@"®"];

        // if (newMessage.editedTimestamp != nil) {
        //     content = [content stringByAppendingString:@" (edited)"];
        // }

        {
            newMessage.emojis = NSMutableArray.new;
            // emojis
            NSRegularExpression *regex            = [NSRegularExpression
                regularExpressionWithPattern:@"\\<(a?):(.*?):(\\d+)\\>"
                                     options:NSRegularExpressionCaseInsensitive
                                       error:NULL];
            NSTextCheckingResult *embeddedMention = [regex
                firstMatchInString:content
                           options:0
                             range:NSMakeRange(0, content.length)];
            while (embeddedMention) {
                BOOL isAnimated     = [[content substringWithRange:[embeddedMention rangeAtIndex:1]] isEqualToString:@"a"];
                NSString *emojiName = [content substringWithRange:[embeddedMention rangeAtIndex:2]];
                NSString *emojiID   = [content substringWithRange:[embeddedMention rangeAtIndex:3]];
                // https://cdn.discordapp.com/emojis/%@.png
                content        = [content
                    stringByReplacingCharactersInRange:embeddedMention.range
                                            withString:@"\u00A0\u00A0\u00A0\u00A0\u00A0\u200B"];
                DCEmoji *emoji = [DCServerCommunicator.sharedInstance emojiForSnowflake:emojiID];
                if (!emoji) {
                    emoji           = [DCEmoji new];
                    emoji.name      = emojiName;
                    emoji.snowflake = emojiID;
                    emoji.animated  = isAnimated;
                    [DCServerCommunicator.sharedInstance setEmoji:emoji forSnowflake:emoji.snowflake];
                }
                if (emoji && !emoji.image) {
                    emoji.image                = [UIImage new];
                    NSURL *emojiURL            = [NSURL URLWithString:[NSString
                                                               stringWithFormat:@"https://cdn.discordapp.com/emojis/%@.%@?size=32",
                                                                                emoji.snowflake,
                                                                                emoji.animated ? @"gif" : @"png"]];
                    SDWebImageManager *manager = [SDWebImageManager sharedManager];
                    [manager downloadImageWithURL:emojiURL
                                          options:SDWebImageRetryFailed
                                         progress:nil
                                        completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                            if (!image || !finished) {
                                                NSLog(@"Failed to load emoji image with URL %@: %@", emojiURL, error);
                                                return;
                                            }
                                            // NSLog(@"Loaded emoji %@", emoji.name);
                                            emoji.image = image;
                                        }];
                }
                [newMessage.emojis addObject:@[ emoji, @(embeddedMention.range.location) ]];
                embeddedMention = [regex firstMatchInString:content options:0 range:NSMakeRange(0, content.length)];
            }
        }

        newMessage.content = content;

        // Calculate height of content to be used when showing messages in a
        // tableview contentHeight does NOT include height of the embeded images or
        // account for height of a grouped message

        CGSize authorNameSize = [[newMessage.author 
            displayNameInGuild:DCServerCommunicator.sharedInstance.selectedChannel.parentGuild]
                 sizeWithFont:[UIFont boldSystemFontOfSize:15]
            constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                lineBreakMode:(NSLineBreakMode)UILineBreakModeWordWrap];
        CGSize contentSize = [newMessage.content
                 sizeWithFont:[UIFont systemFontOfSize:14]
            constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                lineBreakMode:(NSLineBreakMode)UILineBreakModeWordWrap];
        contentSize.height = ceil(contentSize.height);

        newMessage.attributedContent = nil;
        if ([newMessage.content length] > 0) {
            NSAttributedString *attributedText = [[DCMarkdownParser sharedParser]
                attributedStringFromMarkdown:newMessage.content];
            if (attributedText) {
                newMessage.attributedContent = attributedText;
                newMessage.content = attributedText.string;
                // recalc emoji positions — markdown link replacement can shorten the string
                NSRange range = NSMakeRange(0, newMessage.content.length);
                for (NSUInteger idx = 0; idx < newMessage.emojis.count; idx++) {
                    NSArray *emojiInfo = newMessage.emojis[idx];
                    DCEmoji *emoji = emojiInfo[0];
                    NSNumber *location = emojiInfo[1];
                    NSRange found = [newMessage.content rangeOfString:@"\u00A0\u00A0\u00A0\u00A0\u200B"
                                                  options:NSLiteralSearch
                                                    range:range];
                    if (found.location == NSNotFound) {
                        DBGLOG(@"Failed to find emoji %@ in content %@", emoji.name, newMessage.content);
                        break;
                    }
                    if (found.location != [location unsignedIntValue]) {
                        [newMessage.emojis replaceObjectAtIndex:idx withObject:@[ emoji, @(found.location) ]];
                    }
                    range.location = found.location + found.length;
                    range.length = newMessage.content.length - range.location;
                }
                // Recalculate height using DTCoreText layout engine for accuracy
                if (newMessage.attributedContent) {
                    DTCoreTextLayouter *layouter = [[DTCoreTextLayouter alloc] 
                        initWithAttributedString:newMessage.attributedContent];
                    CGRect layoutRect = CGRectMake(0, 0, contentWidth, CGFLOAT_HEIGHT_UNKNOWN);
                    DTCoreTextLayoutFrame *layoutFrame = [layouter layoutFrameWithRect:layoutRect 
                                                                                 range:NSMakeRange(0, 0)];
                    contentSize.height = ceil(CGRectGetHeight(layoutFrame.frame));
                }
            }
        }

        // Pretty "(edited)" tag — CoreText attributes for iOS 5 compatibility
        if (newMessage.editedTimestamp != nil) {
            if (!newMessage.attributedContent) {
                newMessage.attributedContent = [[NSAttributedString alloc]
                    initWithString:newMessage.content
                        attributes:@{
                            (NSString *)kCTFontAttributeName: CFBridgingRelease(
                                CTFontCreateWithName((__bridge CFStringRef)[UIFont systemFontOfSize:14].fontName, 14, NULL))
                        }];
            }
            NSMutableAttributedString *mutable = [newMessage.attributedContent mutableCopy];
            NSMutableDictionary *editedAttrs = [@{
                (NSString *)kCTFontAttributeName: CFBridgingRelease(
                    CTFontCreateWithName((__bridge CFStringRef)[UIFont systemFontOfSize:10].fontName, 10, NULL)),
                (NSString *)kCTForegroundColorAttributeName: (__bridge id)[UIColor colorWithRed:128/255.0f
                                                                                          green:128/255.0f
                                                                                           blue:128/255.0f
                                                                                          alpha:1.0f].CGColor
            } mutableCopy];
            if (VERSION_MIN(@"6.0")) {
                NSShadow *shadow = [NSShadow new];
                shadow.shadowColor = [UIColor blackColor];
                shadow.shadowOffset = CGSizeMake(0, 1);
                shadow.shadowBlurRadius = 0;
                editedAttrs[NSShadowAttributeName] = shadow;
            }
            [mutable appendAttributedString:[[NSAttributedString alloc]
                initWithString:@" (edited)"
                    attributes:editedAttrs]];
            newMessage.attributedContent = mutable;
        }

        // Recalculate cell height after all content modifications
        if (newMessage.attributedContent) {
            DTCoreTextLayouter *layouter = [[DTCoreTextLayouter alloc] 
                initWithAttributedString:newMessage.attributedContent];
            CGRect layoutRect = CGRectMake(0, 0, contentWidth, CGFLOAT_HEIGHT_UNKNOWN);
            DTCoreTextLayoutFrame *layoutFrame = [layouter layoutFrameWithRect:layoutRect 
                                                                         range:NSMakeRange(0, 0)];
            contentSize.height = ceil(CGRectGetHeight(layoutFrame.frame));
        }
        newMessage.textHeight = ceil(contentSize.height) + 2;



        // types of messages we display specially
        BOOL cond = (
            newMessage.messageType == 6 
            || (newMessage.messageType != 18 
                && (
                    newMessage.messageType < 1 
                    || newMessage.messageType > 8
                )
            )
        );
        // Calculate minimum cell height — author name + at least one line of text + padding
        NSCharacterSet *invisibleChars = [NSCharacterSet characterSetWithCharactersInString:@"\u00A0\u200B\n\r\t "];
        BOOL hasVisibleContent = [[newMessage.content stringByTrimmingCharactersInSet:invisibleChars] length] > 0
            || newMessage.emojis.count > 0;
        CGFloat minHeight = (cond ? authorNameSize.height : 0) + (hasVisibleContent ? [UIFont systemFontOfSize:14].lineHeight : 0) + 10;
        newMessage.contentHeight = MAX(
            (cond ? authorNameSize.height : 0)
                + (newMessage.attachmentCount ? (hasVisibleContent ? contentSize.height : 0) : MAX(contentSize.height, 18))
                + 10
                + (newMessage.referencedMessage != nil ? 16 : 0),
            minHeight
        );
        newMessage.authorNameWidth = 60 + authorNameSize.width;
    }

    return newMessage;
}

+ (DCGuild *)convertJsonGuild:(NSDictionary *)jsonGuild withMembers:(NSArray *)members {
    DCGuild *newGuild  = DCGuild.new;
    newGuild.userRoles = NSMutableArray.new;
    newGuild.roles     = NSMutableDictionary.new;
    newGuild.members   = NSMutableArray.new;
    newGuild.emojis    = NSMutableDictionary.new;

    // Get emojis
    for (NSDictionary *emoji in [jsonGuild objectForKey:@"emojis"]) {
        [newGuild.emojis setObject:[DCTools convertJsonEmoji:emoji cache:true]
                            forKey:[emoji objectForKey:@"id"]];
    }

    // Get @everyone role
    for (NSDictionary *guildRole in [jsonGuild objectForKey:@"roles"]) {
        if ([[guildRole objectForKey:@"name"] isEqualToString:@"@everyone"]) {
            [newGuild.userRoles addObject:[guildRole objectForKey:@"id"]];
        }
        [newGuild.roles
            setObject:[DCTools convertJsonRole:guildRole cache:true]
               forKey:[guildRole objectForKey:@"id"]];
    }

    // Get roles of the current user
    if (members && members.count > 0 && [members[0] objectForKey:@"user_id"]) {
        // READY merged_members
        for (NSDictionary *member in members) {
            if ([[member objectForKey:@"user_id"] isEqualToString:DCServerCommunicator.sharedInstance.snowflake]) {
                [newGuild.userRoles addObjectsFromArray:[member objectForKey:@"roles"]];
            }
            DCUser *user = [DCServerCommunicator.sharedInstance userForSnowflake:[member objectForKey:@"user_id"]];
            NSString *nick = [member objectForKey:@"nick"];
            if (user && nick && (NSNull *)nick != [NSNull null] && nick.length > 0
                && newGuild.snowflake && (NSNull *)newGuild.snowflake != [NSNull null]) {
                if (!user.guildNicknames) user.guildNicknames = NSMutableDictionary.new;
                user.guildNicknames[newGuild.snowflake] = nick;
            }
        }
    } else {
        // GUILD_CREATE
        for (NSDictionary *member in [jsonGuild objectForKey:@"members"]) {
            DCUser *user = [DCTools convertJsonUser:[member objectForKey:@"user"] cache:true];
            [DCServerCommunicator.sharedInstance setUser:user
                                            forSnowflake:[member valueForKeyPath:@"user.id"]];
            if ([[member valueForKeyPath:@"user.id"] isEqualToString:DCServerCommunicator.sharedInstance.snowflake]) {
                [newGuild.userRoles addObjectsFromArray:[member objectForKey:@"roles"]];
            }
            NSString *nick = [member objectForKey:@"nick"];
            if (nick && (NSNull *)nick != [NSNull null] && nick.length > 0 
                && newGuild.snowflake) { // add nil check for snowflake
                if (!user.guildNicknames) user.guildNicknames = NSMutableDictionary.new;
                user.guildNicknames[newGuild.snowflake] = nick;
            }
        }
    }

    newGuild.name = [jsonGuild objectForKey:@"name"];

    // add new types here.
    newGuild.snowflake = [jsonGuild objectForKey:@"id"];
    newGuild.channels  = NSMutableArray.new;

    NSNumber *longId = @([newGuild.snowflake longLongValue]);

    int selector = (int)(([longId longLongValue] >> 22) % 6);

    newGuild.icon = [DCUser defaultAvatars][selector];
    /*CGSize itemSize = CGSizeMake(40, 40);
     UIGraphicsBeginImageContextWithOptions(itemSize, NO,
     UIScreen.mainScreen.scale); CGRect imageRect = CGRectMake(0.0, 0.0,
     itemSize.width, itemSize.height); [newGuild.icon  drawInRect:imageRect];
     newGuild.icon = UIGraphicsGetImageFromCurrentImageContext();
     UIGraphicsEndImageContext();*/

    SDWebImageManager *manager = [SDWebImageManager sharedManager];

    if ([jsonGuild objectForKey:@"icon"] && [jsonGuild objectForKey:@"icon"] != [NSNull null]) {
        NSURL *iconURL = [NSURL URLWithString:[NSString
                                                  stringWithFormat:@"https://cdn.discordapp.com/icons/%@/%@.png?size=80",
                                                                   newGuild.snowflake, [jsonGuild objectForKey:@"icon"]]];
        [manager downloadImageWithURL:iconURL
                              options:SDWebImageRetryFailed
                             progress:nil
                            completed:^(UIImage *icon, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                @autoreleasepool {
                                    if (!icon || !finished) {
                                        NSLog(@"Failed to load guild icon with URL %@: %@", iconURL, error);
                                        return;
                                    }
                                    newGuild.icon   = icon;
                                    CGSize itemSize = CGSizeMake(40, 40);
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        UIGraphicsBeginImageContextWithOptions(
                                            itemSize, NO, UIScreen.mainScreen.scale
                                        );
                                        CGRect imageRect = CGRectMake(
                                            0.0, 0.0, itemSize.width,
                                            itemSize.height
                                        );
                                        [newGuild.icon drawInRect:imageRect];
                                        newGuild.icon = UIGraphicsGetImageFromCurrentImageContext();
                                        UIGraphicsEndImageContext();
                                        [NSNotificationCenter.defaultCenter
                                            postNotificationName:@"RELOAD GUILD"
                                                          object:newGuild];
                                    });
                                }
                            }];
    }

    if ([jsonGuild objectForKey:@"banner"] && [jsonGuild objectForKey:@"banner"] != [NSNull null]) {
        NSURL *bannerURL = [NSURL URLWithString:[NSString
                                                    stringWithFormat:@"https://cdn.discordapp.com/banners/%@/%@.png?size=320",
                                                                     newGuild.snowflake, [jsonGuild objectForKey:@"banner"]]];
        [manager downloadImageWithURL:bannerURL
                              options:SDWebImageRetryFailed
                             progress:nil
                            completed:^(UIImage *banner, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                @autoreleasepool {
                                    if (!banner || !finished) {
                                        NSLog(@"Failed to load guild banner with URL %@: %@", bannerURL, error);
                                        return;
                                    }
                                    newGuild.banner = banner;
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        UIGraphicsEndImageContext();
                                    });
                                }
                            }];
    }

    NSMutableArray *categories = NSMutableArray.new;

    NSArray *combined             = [[jsonGuild objectForKey:@"channels"] arrayByAddingObjectsFromArray:[jsonGuild objectForKey:@"threads"]];
    NSMutableDictionary *channels = NSMutableDictionary.new;
    for (NSDictionary *jsonChannel in combined) {
        // regardless of implementation or permissions, add to channels list so they're visible in <#snowflake>
        DCChannel *newChannel = DCChannel.new;

        newChannel.snowflake = [jsonChannel objectForKey:@"id"];
        newChannel.parentID  = [jsonChannel objectForKey:@"parent_id"];
        newChannel.name      = [jsonChannel objectForKey:@"name"];
        newChannel.lastMessageId =
            [jsonChannel objectForKey:@"last_message_id"];
        newChannel.parentGuild = newGuild;
        newChannel.type        = [[jsonChannel objectForKey:@"type"] intValue];
        NSString *rawPosition  = [jsonChannel objectForKey:@"position"];
        newChannel.position    = rawPosition ? [rawPosition intValue] : 0;
        newChannel.writeable   = true;

        // check if channel is muted
        if ([DCServerCommunicator.sharedInstance.userChannelSettings
                objectForKey:newChannel.snowflake]) {
            newChannel.muted = true;
        }

        // Make sure jsonChannel is a text channel or a category
        // we dont want to include voice channels in the text channel list
        if ([[jsonChannel objectForKey:@"type"] isEqual:@(DCChannelTypeGuildText)] ||         // text channel
            [[jsonChannel objectForKey:@"type"] isEqual:@(DCChannelTypeGuildAnnouncement)] || // announcements
            [[jsonChannel objectForKey:@"type"] isEqual:@(DCChannelTypeGuildCategory)]) {     // category
            // Allow code is used to determine if the user should see the
            // channel in question.
            /*
             0 - No overrides. Channel should be created

             1 - Hidden by role. Channel should not be created unless another
             role contradicts (code 2)

             2 - Shown by role. Channel should be created unless hidden by
             member overwrite (code 3)

             3 - Hidden by member. Channel should not be created

             4 - Shown by member. Channel should be created

             3 & 4 are mutually exclusive
             */
            int allowCode = 0;
            BOOL canWrite = true;

            // Calculate permissions
            NSArray *rawOverwrites =
                [jsonChannel objectForKey:@"permission_overwrites"];
            // sort with role priority
            NSArray *overwrites = [rawOverwrites sortedArrayUsingComparator:
                                                     ^NSComparisonResult(NSDictionary *perm1, NSDictionary *perm2) {
                                                         DCRole *role1 = [newGuild.roles objectForKey:[perm1 objectForKey:@"id"]];
                                                         DCRole *role2 = [newGuild.roles objectForKey:[perm2 objectForKey:@"id"]];
                                                         return role1.position < role2.position ? NSOrderedAscending : NSOrderedDescending;
                                                     }];
            for (NSDictionary *permission in overwrites) {
                uint64_t type     = [[permission objectForKey:@"type"] longLongValue];
                NSString *idValue = [permission objectForKey:@"id"];
                uint64_t deny     = [[permission objectForKey:@"deny"] longLongValue];
                uint64_t allow    = [[permission objectForKey:@"allow"] longLongValue];

                if (type == 0) { // Role overwrite
                    if ([newGuild.userRoles containsObject:idValue]) {
                        if ((deny & DCPermissionSendMessages) == DCPermissionSendMessages) {
                            canWrite = false;
                        }
                        if ((deny & DCPermissionViewChannel) == DCPermissionViewChannel) {
                            allowCode = 1;
                        }
                        if ((allow & DCPermissionSendMessages) == DCPermissionSendMessages) {
                            canWrite = true;
                        }
                        if ((allow & DCPermissionViewChannel) == DCPermissionViewChannel) {
                            allowCode = 2;
                        }
                    }
                } else if (type == 1) { // Member overwrite, break on these
                    if ([idValue isEqualToString:
                                     DCServerCommunicator.sharedInstance.snowflake]) {
                        if ((deny & DCPermissionSendMessages) == DCPermissionSendMessages) {
                            canWrite = false;
                        }
                        if ((deny & DCPermissionViewChannel) == DCPermissionViewChannel) {
                            allowCode = 3;
                        }
                        if ((allow & DCPermissionSendMessages) == DCPermissionSendMessages) {
                            canWrite = true;
                        }
                        if ((allow & DCPermissionViewChannel) == DCPermissionViewChannel) {
                            allowCode = 4;
                        }
                        break;
                    }
                }
            }

            newChannel.writeable = canWrite || [[jsonGuild objectForKey:@"owner_id"] isEqualToString:DCServerCommunicator.sharedInstance.snowflake];
            // ignore perms for guild categories
            if (newChannel.type == DCChannelTypeGuildCategory) { // category
                [categories addObject:newChannel];
            } else {
                [newGuild.channels addObject:newChannel];
            }
        }
        [channels setObject:newChannel forKey:newChannel.snowflake];
    }

    // refer to https://github.com/Rapptz/discord.py/issues/2392#issuecomment-707455919
    [newGuild.channels sortUsingComparator:^NSComparisonResult(
                           DCChannel *channel1, DCChannel *channel2
    ) {
        if ([channel1.parentID isKindOfClass:[NSString class]] && ![channel2.parentID isKindOfClass:[NSString class]]) {
            return NSOrderedDescending;
        } else if (![channel1.parentID isKindOfClass:[NSString class]] && [channel2.parentID isKindOfClass:[NSString class]]) {
            return NSOrderedAscending;
        } else if ([channel1.parentID isKindOfClass:[NSString class]] && [channel2.parentID isKindOfClass:[NSString class]] && ![channel1.parentID isEqualToString:channel2.parentID]) {
            NSUInteger idx1 = [categories indexOfObjectPassingTest:^BOOL(DCChannel *category, NSUInteger idx, BOOL *stop) {
                return [category.snowflake isEqualToString:channel1.parentID];
            }],
                       idx2 = [categories indexOfObjectPassingTest:^BOOL(DCChannel *category, NSUInteger idx, BOOL *stop) {
                           return [category.snowflake isEqualToString:channel2.parentID];
                       }];
            if (idx1 != NSNotFound && idx2 != NSNotFound) {
                DCChannel *parent1 = [categories objectAtIndex:idx1];
                DCChannel *parent2 = [categories objectAtIndex:idx2];
                if (parent1.position < parent2.position) {
                    return NSOrderedAscending;
                } else if (parent1.position > parent2.position) {
                    return NSOrderedDescending;
                }
            }
        }

#warning TODO: voice channels at the bottom
        // if (channel1.type < channel2.type) {
        //     return NSOrderedAscending;
        // } else if (channel1.type > channel2.type) {
        //     return NSOrderedDescending;
        // } else
        if (channel1.position < channel2.position) {
            return NSOrderedAscending;
        } else if (channel1.position > channel2.position) {
            return NSOrderedDescending;
        } else {
            return [channel1.snowflake compare:channel2.snowflake];
        }
    }];

    // Add categories to the guild
    for (DCChannel *category in categories) {
        int i = 0;
        for (DCChannel *channel in newGuild.channels) {
            if (channel.type == DCChannelTypeGuildCategory
                || channel.parentID == nil
                || (NSNull *)channel.parentID == [NSNull null]) {
                // If the channel is a category or has no parent, skip it
                i++;
                continue;
            }
            if ([channel.parentID isEqualToString:category.snowflake]) {
                [newGuild.channels insertObject:category atIndex:i];
                break;
            }
            i++;
        }
    }

    [DCServerCommunicator.sharedInstance.channels addEntriesFromDictionary:channels];

    return newGuild;
}

+ (NSString *)parseMessage:(NSString *)messageString withGuild:(DCGuild *)guild {
    // convert :emoji: to <a:emoji:snowflake> or <emoji:snowflake>
    {
        static dispatch_once_t onceToken;
        static NSRegularExpression *regex;
        dispatch_once(&onceToken, ^{
            regex = [NSRegularExpression
                regularExpressionWithPattern:@":(\\w+):"
                                     options:NSRegularExpressionCaseInsensitive
                                       error:NULL];
        });
        NSTextCheckingResult *embeddedMention = [regex
            firstMatchInString:messageString
                       options:0
                         range:NSMakeRange(0, messageString.length)];

        while (embeddedMention) {
            NSString *emojiName = [messageString substringWithRange:[embeddedMention rangeAtIndex:1]];
            DCEmoji *emoji      = nil;
            if (guild) {
                emoji = [guild.emojis.allValues
                            filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DCEmoji *obj, NSDictionary *bindings) {
                                return [obj.name isEqualToString:emojiName];
                            }]]
                            .firstObject;
            }
            if (!emoji) {
                __block DCEmoji *foundEmoji = nil;
                dispatch_sync(DCServerCommunicator.sharedInstance.accessQueue, ^{
                    foundEmoji = [DCServerCommunicator.sharedInstance.loadedEmojis.allValues
                        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DCEmoji *obj, NSDictionary *bindings) {
                            return [obj.name isEqualToString:emojiName];
                        }]].firstObject;
                });
                emoji = foundEmoji;
            }
            if (emoji) {
                NSString *replacement = [NSString stringWithFormat:@"<%@:%@:%@>",
                                                                   emoji.animated ? @"a" : @"", emojiName, emoji.snowflake];
                messageString         = [messageString stringByReplacingCharactersInRange:embeddedMention.range withString:replacement];
            } else {
                DBGLOG(@"Missing emoji: %@", emojiName);
            }
            embeddedMention = [regex firstMatchInString:messageString
                                                options:0
                                                  range:NSMakeRange(
                                                            embeddedMention.range.location + embeddedMention.range.length,
                                                            messageString.length - (embeddedMention.range.location + embeddedMention.range.length)
                                                        )];
        }
    }

    // convert @username/@role to <@{!,&}snowflake>
    {
        static dispatch_once_t onceToken;
        static NSRegularExpression *regex;
        dispatch_once(&onceToken, ^{
            regex = [NSRegularExpression
                regularExpressionWithPattern:@"@(\\w+)"
                                     options:NSRegularExpressionCaseInsensitive
                                       error:NULL];
        });
        NSTextCheckingResult *embeddedMention = [regex
            firstMatchInString:messageString
                       options:0
                         range:NSMakeRange(0, messageString.length)];

        while (embeddedMention) {
            NSString *mentionName  = [messageString substringWithRange:[embeddedMention rangeAtIndex:1]];
            DCSnowflake *snowflake = nil;
            BOOL isUser            = YES;
            {
                __block id obj = nil;
                dispatch_sync(DCServerCommunicator.sharedInstance.accessQueue, ^{
                    obj = [DCServerCommunicator.sharedInstance.loadedUsers.allValues
                        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DCUser *obj, NSDictionary *bindings) {
                            return [obj.username isEqualToString:mentionName] || [obj.globalName isEqualToString:mentionName];
                        }]].firstObject;
                });
                if (!obj && guild) {
                    isUser = NO;
                    obj    = [guild.roles.allValues
                              filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DCRole *obj, NSDictionary *bindings) {
                                  return [obj.name isEqualToString:mentionName];
                              }]]
                              .firstObject;
                }
                if (obj) {
                    if (isUser) {
                        snowflake = ((DCUser *)obj).snowflake;
                    } else {
                        snowflake = ((DCRole *)obj).snowflake;
                    }
                }
            }
            if (snowflake) {
                NSString *replacement = [NSString stringWithFormat:@"<@%c%@>", isUser ? '!' : '&', snowflake];
                messageString         = [messageString stringByReplacingCharactersInRange:embeddedMention.range
                                                                       withString:replacement];
            } else {
                DBGLOG(@"Missing mention: %@", mentionName);
            }
            embeddedMention = [regex firstMatchInString:messageString
                                                options:0
                                                  range:NSMakeRange(
                                                            embeddedMention.range.location + embeddedMention.range.length,
                                                            messageString.length - (embeddedMention.range.location + embeddedMention.range.length)
                                                        )];
        }
    }

    // convert #channel to <#snowflake>
    if (guild) {
        static dispatch_once_t onceToken;
        static NSRegularExpression *regex;
        dispatch_once(&onceToken, ^{
            regex = [NSRegularExpression
                regularExpressionWithPattern:@"#(\\w+)"
                                     options:NSRegularExpressionCaseInsensitive
                                       error:NULL];
        });
        NSTextCheckingResult *embeddedMention = [regex
            firstMatchInString:messageString
                       options:0
                         range:NSMakeRange(0, messageString.length)];

        while (embeddedMention) {
            NSString *channelName = [messageString substringWithRange:[embeddedMention rangeAtIndex:1]];
            DCChannel *channel    = [guild.channels
                                     filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DCChannel *obj, NSDictionary *bindings) {
                                         return [obj.name isEqualToString:channelName];
                                     }]]
                                     .firstObject;
            if (channel) {
                NSString *replacement = [NSString stringWithFormat:@"<#%@>", channel.snowflake];
                messageString         = [messageString stringByReplacingCharactersInRange:embeddedMention.range withString:replacement];
            } else {
                DBGLOG(@"Missing channel: %@", channelName);
            }
            embeddedMention = [regex firstMatchInString:messageString
                                                options:0
                                                  range:NSMakeRange(
                                                            embeddedMention.range.location + embeddedMention.range.length,
                                                            messageString.length - (embeddedMention.range.location + embeddedMention.range.length)
                                                        )];
        }
    }
    return messageString;
}

//+ (void)joinGuild:(NSString *)inviteCode {
//    // dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0),
//    // ^{
//    NSURL *guildURL = [NSURL
//        URLWithString:[NSString stringWithFormat:
//                                    @"https://discordapp.com/api/v9/invite/%@",
//                                    inviteCode]];
//
//    NSMutableURLRequest *urlRequest = [NSMutableURLRequest
//         requestWithURL:guildURL
//            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
//        timeoutInterval:15];
//    [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];
//
//    urlRequest.HTTPMethod = @"POST";
//
//    //[urlRequest setHTTPBody:[NSData dataWithBytes:[messageString UTF8String]
//    // length:[messageString length]]];
//    [urlRequest addValue:DCServerCommunicator.sharedInstance.token
//        forHTTPHeaderField:@"Authorization"];
//    [urlRequest addValue:@"application/json"
//        forHTTPHeaderField:@"Content-Type"];
//
//    /*NSError *error = nil;
//     NSHTTPURLResponse *responseCode = nil;
//     int attempts = 0;
//     while (attempts == 0 || (attempts <= 10 && error.code ==
//     NSURLErrorTimedOut)) { attempts++; error = nil; [UIApplication
//     sharedApplication].networkActivityIndicatorVisible++; [DCTools
//     checkData:[NSURLConnection sendSynchronousRequest:urlRequest
//     returningResponse:&responseCode error:&error] withError:error];
//     [UIApplication sharedApplication].networkActivityIndicatorVisible--;*/
//    dispatch_async(dispatch_get_main_queue(), ^{
//        [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
//    });
//    [NSURLConnection
//        sendAsynchronousRequest:urlRequest
//                          queue:[NSOperationQueue currentQueue]
//              completionHandler:^(
//                  NSURLResponse *response, NSData *data, NSError *connError
//              ) {
//                  dispatch_sync(dispatch_get_main_queue(), ^{
//                      [UIApplication sharedApplication]
//                          .networkActivityIndicatorVisible = NO;
//                  });
//              }];
//    //}
//    //});
//}


// New joinGuild function that uses new header. Should be safer.
+ (void)joinGuild:(NSString *)inviteCode {
    NSMutableURLRequest *urlRequest = [DCServerCommunicator
                                       requestWithPath:[NSString stringWithFormat:@"/invite/%@", inviteCode]
                                       token:DCServerCommunicator.sharedInstance.token];
    urlRequest.HTTPMethod = @"POST";
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    });
    [NSURLConnection
     sendAsynchronousRequest:urlRequest
     queue:[NSOperationQueue currentQueue]
     completionHandler:^(NSURLResponse *response, NSData *data, NSError *connError) {
         dispatch_sync(dispatch_get_main_queue(), ^{
             [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
         });
     }];
}


+ (void)checkForAppUpdate {
    // this is just via the "XML Update Server"
    dispatch_async(
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
        ^{
            NSURL *randomEndpoint = [NSURL
                URLWithString:[NSString
                                  stringWithFormat:
                                      @"http://5.230.249.85:8814/update?v=%@",
                                      appVersion]];
            NSURLResponse *response;
            NSError *error;

            NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
            request.URL                  = randomEndpoint;
            request.HTTPMethod           = @"GET";
            [request setValue:@"application/json"
                forHTTPHeaderField:@"Content-Type"];
            request.timeoutInterval = 10;

            NSData *data = [NSURLConnection sendSynchronousRequest:request
                                                 returningResponse:&response
                                                             error:&error];

            if (data) {
                NSDictionary *response =
                    [NSJSONSerialization JSONObjectWithData:data
                                                    options:0
                                                      error:&error];
                NSNumber *update  = response[@"outdated"];
                NSString *message = response[@"message"];

                if ([update intValue] == 1) {
                    [self alert:@"Update Available" withMessage:message];
                } else {
                    return;
                }
            } else {
                return;
            }
        }
    );
    return;
}

@end
