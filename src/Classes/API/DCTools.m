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
#import "DCEmoji.h"
#import "DCMessage.h"
#import "DCRole.h"
#import "DCServerCommunicator.h"
#import "DCUser.h"
#import "NSString+Emojize.h"
#import "QuickLook/QuickLook.h"
#import "SDWebImageManager.h"
#include "TSMarkdownParser.h"
#import "ThumbHash.h"
#import "UIImage+animatedGIF.h"
#import "UILazyImage.h"

// https://discord.gg/X4NSsMC

@implementation DCTools

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
    if (cache && [DCServerCommunicator.sharedInstance.loadedUsers objectForKey:[jsonUser objectForKey:@"id"]]) {
        // return pre-cached
        return [DCServerCommunicator.sharedInstance.loadedUsers objectForKey:[jsonUser objectForKey:@"id"]];
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
        [DCServerCommunicator.sharedInstance.loadedUsers
            setValue:newUser
              forKey:newUser.snowflake];
    }

    return newUser;
}

+ (void)getUserAvatar:(DCUser *)user {
    @autoreleasepool {
        user.profileImage     = [UIImage new];
        user.avatarDecoration = [UIImage new];

        SDWebImageManager *manager = [SDWebImageManager sharedManager];
        // Load profile image
        NSURL *avatarURL =
            [NSURL URLWithString:[NSString stringWithFormat:
                                               @"https://cdn.discordapp.com/avatars/%@/%@.png?size=80",
                                               user.snowflake, user.avatarID]];
        [manager downloadImageWithURL:avatarURL
                              options:0
                             progress:nil
                            completed:^(UIImage *retrievedImage, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                @autoreleasepool {
                                    if (retrievedImage && finished) {
                                        user.profileImage = retrievedImage;
                                        dispatch_async(dispatch_get_main_queue(), ^{
                                            [NSNotificationCenter.defaultCenter
                                                postNotificationName:
                                                    @"RELOAD USER DATA"
                                                              object:user];
                                        });
                                    } else {
                                        // NSLog(@"Failed to download user profile image with URL %@: %@", avatarURL, error);
                                        int selector = 0;

                                        if (user.discriminator == 0) {
                                            NSNumber *longId = @([user.snowflake longLongValue]);
                                            selector         = ([longId longLongValue] >> 22) % 6;
                                        } else {
                                            selector = user.discriminator % 5;
                                        }
                                        user.profileImage = [DCUser defaultAvatars][selector];
                                    }
                                }
                            }];

        if (!user.avatarDecorationID || (NSNull *)user.avatarDecorationID == [NSNull null]) {
            return;
        }
        NSURL *avatarDecorationURL = [NSURL URLWithString:[NSString
                                                              stringWithFormat:@"https://cdn.discordapp.com/avatar-decoration-presets/%@.png?size=96&passthrough=false",
                                                                               user.avatarDecorationID]];
        [manager downloadImageWithURL:avatarDecorationURL
                              options:0
                             progress:nil
                            completed:^(UIImage *retrievedImage, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                if (!retrievedImage || !finished) {
                                    NSLog(@"Failed to download user avatar decoration with URL %@: %@", avatarDecorationURL, error);
                                    return;
                                }
                                user.avatarDecoration = retrievedImage;
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [NSNotificationCenter.defaultCenter
                                        postNotificationName:
                                            @"RELOAD USER DATA"
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
        [DCServerCommunicator.sharedInstance.loadedRoles
            setValue:newRole
              forKey:newRole.snowflake];
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
                              options:0
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
    if (!image) {
        return nil;
    }
    if (image.images.count > 1) {
        // If the image is animated, don't scale
        UILazyImage *lazyImage = [UILazyImage new];
        lazyImage.image        = image;
        lazyImage.imageURL     = url;
        return lazyImage;
    }
    CGFloat aspectRatio = image.size.width / image.size.height;
    int newWidth        = 200 * aspectRatio;
    int newHeight       = 200;
    UIGraphicsBeginImageContextWithOptions(
        CGSizeMake(newWidth, newHeight),
        NO,
        0.0
    );
    [image drawInRect:CGRectMake(0, 0, newWidth, newHeight)];
    UILazyImage *newImage = [UILazyImage new];
    newImage.image        = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    newImage.imageURL     = url;
    return newImage;
}

+ (DCEmoji *)convertJsonEmoji:(NSDictionary *)jsonEmoji cache:(BOOL)cache {
    if (cache && [DCServerCommunicator.sharedInstance.loadedEmojis objectForKey:[jsonEmoji objectForKey:@"id"]]) {
        // return pre-cached
        return [DCServerCommunicator.sharedInstance.loadedEmojis objectForKey:[jsonEmoji objectForKey:@"id"]];
    }

    DCEmoji *newEmoji  = DCEmoji.new;
    newEmoji.snowflake = [jsonEmoji objectForKey:@"id"];
    newEmoji.name      = [jsonEmoji objectForKey:@"name"];
    newEmoji.animated  = [[jsonEmoji objectForKey:@"animated"] boolValue];

    // Save to DCServerCommunicator.loadedEmojis
    if (cache) {
        [DCServerCommunicator.sharedInstance.loadedEmojis
            setValue:newEmoji
              forKey:newEmoji.snowflake];
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

        if (![DCServerCommunicator.sharedInstance.loadedUsers objectForKey:authorId]
            && authorId != nil && ![authorId isKindOfClass:[NSNull class]]) {
            [DCTools convertJsonUser:[jsonMessage valueForKeyPath:@"author"]
                               cache:true];
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

            if (![DCServerCommunicator.sharedInstance.loadedUsers
                    objectForKey:referencedAuthorId]) {
                [DCTools
                    convertJsonUser:
                        [jsonMessage valueForKeyPath:@"referenced_message.author"]
                              cache:true];
            }

            referencedMessage.author =
                [DCServerCommunicator.sharedInstance.loadedUsers
                    objectForKey:referencedAuthorId];
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
            CGSize authorNameSize             = [referencedMessage.author.globalName
                     sizeWithFont:[UIFont boldSystemFontOfSize:10]
                constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                    lineBreakMode:(NSLineBreakMode)UILineBreakModeWordWrap];
            referencedMessage.authorNameWidth = 80 + authorNameSize.width;

            newMessage.referencedMessage = referencedMessage;
        }

        newMessage.author =
            [DCServerCommunicator.sharedInstance.loadedUsers objectForKey:authorId];
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
        dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ";
        dateFormatter.locale     = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];

        newMessage.timestamp =
            [dateFormatter dateFromString:[jsonMessage objectForKey:@"timestamp"]];
        if (newMessage.timestamp == nil) {
            dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
            newMessage.timestamp     = [dateFormatter
                dateFromString:[jsonMessage objectForKey:@"timestamp"]];
        }

        if ([jsonMessage objectForKey:@"edited_timestamp"] != [NSNull null]) {
            newMessage.editedTimestamp = [dateFormatter
                dateFromString:[jsonMessage objectForKey:@"edited_timestamp"]];
            if (newMessage.editedTimestamp == nil) {
                dateFormatter.dateFormat   = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
                newMessage.editedTimestamp = [dateFormatter
                    dateFromString:[jsonMessage
                                       objectForKey:@"edited_timestamp"]];
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
        // dispatch_sync(dispatch_get_main_queue(), ^{
        // Load embeded images from both links and attatchments
        NSArray *embeds = [jsonMessage objectForKey:@"embeds"];
        if (embeds) {
            for (NSDictionary *embed in embeds) {
                NSString *embedType = [embed objectForKey:@"type"];
                if ([embedType isEqualToString:@"image"]
                    || (
                        [embedType isEqualToString:@"gifv"]
                        && ([[embed valueForKeyPath:@"provider.name"] isEqualToString:@"Tenor"]
                         || [[embed valueForKeyPath:@"provider.name"] isEqualToString:@"Giphy"])
                    )) {
                    newMessage.attachmentCount++;
                    newMessage.content = [newMessage.content stringByReplacingOccurrencesOfString:[embed objectForKey:@"url"] withString:@""];

                    NSString *attachmentURL;

                    if ([embedType isEqualToString:@"gifv"]) {
                        if ([[embed valueForKeyPath:@"provider.name"] isEqualToString:@"Tenor"]) {
                            NSURL *tenorURL = [NSURL URLWithString:[embed valueForKeyPath:@"thumbnail.url"]];
                            NSString *gifId = tenorURL.pathComponents[1];
                            attachmentURL   = [NSString stringWithFormat:@"%@://%@/%@/%@",
                                                                       tenorURL.scheme,
                                                                       tenorURL.host,
                                                                       [gifId stringByReplacingCharactersInRange:NSMakeRange(gifId.length - 1, 1)
                                                                                                      withString:@"C"], // -AAAAC (0x00000002) = HD GIF
                                                                       [tenorURL.pathComponents[2] stringByReplacingOccurrencesOfString:@".png"
                                                                                                                             withString:@".gif"]];
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

                    NSURL *urlString = [NSURL URLWithString:attachmentURL];

                    if (width != 0 || height != 0) {
                        urlString = [NSURL URLWithString:[NSString
                                                             stringWithFormat:@"%@%cwidth=%ld&height=%ld",
                                                                              urlString,
                                                                              [urlString query].length == 0 ? '?' : '&',
                                                                              (long)width, (long)height]];
                    }

                    NSUInteger idx = [newMessage.attachments count];
                    if ([[embed valueForKeyPath:@"thumbnail.placeholder_version"] integerValue] == 1) {
                        UIImage *img = thumbHashToImage([NSData dataWithBase64EncodedString:[embed valueForKeyPath:@"thumbnail.placeholder"]]);
                        [newMessage.attachments addObject:[DCTools scaledImageFromImage:img withURL:urlString]];
                    } else {
                        [newMessage.attachments addObject:@[ @(width), @(height) ]];
                    }

                    if (!DCServerCommunicator.sharedInstance.dataSaver) {
                        SDWebImageManager *manager = [SDWebImageManager sharedManager];
                        [manager downloadImageWithURL:urlString
                                              options:SDWebImageCacheMemoryOnly
                                             progress:nil
                                            completed:^(UIImage *retrievedImage, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                                @autoreleasepool {
                                                    if (!retrievedImage || !finished) {
                                                        NSLog(@"Failed to load embed image with URL %@: %@", urlString, error);
                                                        return;
                                                    }
                                                    [newMessage.attachments replaceObjectAtIndex:idx withObject:[DCTools scaledImageFromImage:retrievedImage withURL:urlString]];

                                                    dispatch_async(dispatch_get_main_queue(), ^{
                                                        [NSNotificationCenter.defaultCenter
                                                            postNotificationName:@"RELOAD MESSAGE DATA"
                                                                          object:newMessage];
                                                    });
                                                }
                                            }];
                    }
                } else if ([embedType isEqualToString:@"video"] ||
                           [embedType isEqualToString:@"gifv"]) {
                    NSURL *attachmentURL;

                    newMessage.content = [newMessage.content stringByReplacingOccurrencesOfString:[embed objectForKey:@"url"] withString:@""];

                    if ([embed valueForKeyPath:@"video.proxy_url"] != nil &&
                        [[embed valueForKeyPath:@"video.proxy_url"]
                            isKindOfClass:[NSString class]]) {
                        attachmentURL = [NSURL URLWithString:[embed valueForKeyPath:@"video.proxy_url"]];
                    } else if ([embed valueForKeyPath:@"video.url"] != nil &&
                               [[embed valueForKeyPath:@"video.url"] isKindOfClass:[NSString class]]) {
                        attachmentURL = [NSURL URLWithString:[embed valueForKeyPath:@"video.url"]];
                    } else {
                        attachmentURL = [NSURL URLWithString:[embed objectForKey:@"url"]];
                    }

                    //[newMessage.attachments
                    // addObject:[[MPMoviePlayerViewController alloc]
                    // initWithContentURL:attachmentURL]];
                    DCChatVideoAttachment *video = [[[NSBundle mainBundle]
                        loadNibNamed:@"DCChatVideoAttachment"
                               owner:self
                             options:nil] objectAtIndex:0];

                    video.videoURL = attachmentURL;

                    NSString *baseURL = [embed objectForKey:@"url"];

                    if ([embed valueForKeyPath:@"thumbnail.proxy_url"] != nil &&
                        [[embed valueForKeyPath:@"thumbnail.proxy_url"]
                            isKindOfClass:[NSString class]]) {
                        baseURL = [embed valueForKeyPath:@"thumbnail.proxy_url"];
                    } else if ([embed valueForKeyPath:@"thumbnail.url"] != nil &&
                               [[embed valueForKeyPath:@"thumbnail.url"]
                                   isKindOfClass:[NSString class]]) {
                        baseURL = [embed valueForKeyPath:@"thumbnail.url"];
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

                    NSURL *urlString = [NSURL URLWithString:baseURL];
                    BOOL isDiscord   = [baseURL
                        hasPrefix:@"https://media.discordapp.net/"];

                    if (isDiscord) {
                        if (width != 0 || height != 0) {
                            urlString = [NSURL URLWithString:
                                                   [NSString stringWithFormat:
                                                                 @"%@%cformat=png&width=%ld&height=%ld",
                                                                 urlString,
                                                                 [urlString query].length == 0 ? '?' : '&',
                                                                 (long)width, (long)height]];
                        } else {
                            urlString = [NSURL URLWithString:
                                                   [NSString stringWithFormat:
                                                                 @"%@%cformat=png",
                                                                 urlString,
                                                                 [urlString query].length == 0 ? '?' : '&']];
                        }
                    } else {
                        urlString = [NSURL URLWithString:
                                               [NSString stringWithFormat:@"%@%cformat=png",
                                                                          urlString,
                                                                          [urlString query].length == 0 ? '?' : '&']];
                    }

                    NSUInteger idx = [newMessage.attachments count];
                    if ([[embed valueForKeyPath:@"thumbnail.placeholder_version"] integerValue] == 1) {
                        UIImage *img          = thumbHashToImage([NSData dataWithBase64EncodedString:[embed valueForKeyPath:@"thumbnail.placeholder"]]);
                        video.thumbnail.image = [DCTools scaledImageFromImage:img withURL:urlString].image;
                        [newMessage.attachments addObject:video];
                    } else {
                        [newMessage.attachments addObject:@[ @(width), @(height) ]];
                    }

                    if (!DCServerCommunicator.sharedInstance.dataSaver) {
                        SDWebImageManager *manager = [SDWebImageManager sharedManager];
                        [manager downloadImageWithURL:urlString
                                              options:SDWebImageCacheMemoryOnly
                                             progress:nil
                                            completed:^(UIImage *retrievedImage, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                                @autoreleasepool {
                                                    if (!retrievedImage || !finished) {
                                                        NSLog(@"Failed to load video thumbnail with URL %@: %@", urlString, error);
                                                        return;
                                                    }
                                                    dispatch_async(
                                                        dispatch_get_main_queue(),
                                                        ^{
                                                            video.thumbnail.image = [DCTools scaledImageFromImage:retrievedImage withURL:nil].image;
                                                            [newMessage.attachments replaceObjectAtIndex:idx withObject:video];
                                                            [NSNotificationCenter.defaultCenter
                                                                postNotificationName:@"RELOAD CHAT DATA"
                                                                              object:newMessage];
                                                        }
                                                    );
                                                }
                                            }];
                    }

                    video.layer.cornerRadius     = 6;
                    video.layer.masksToBounds    = YES;
                    video.userInteractionEnabled = YES;
                    newMessage.attachmentCount++;
                } else {
                    // NSLog(@"unknown embed type %@", embedType);
                    continue;
                }
            }
        }

        NSArray *attachments = [jsonMessage objectForKey:@"attachments"];
        if (attachments) {
            for (NSDictionary *attachment in attachments) {
                NSString *fileType = [attachment objectForKey:@"content_type"];
                if ([fileType rangeOfString:@"image/"].location != NSNotFound) {
                    newMessage.attachmentCount++;

                    NSString *attachmentURL;
                    if ([attachment objectForKey:@"proxy_url"]) {
                        attachmentURL = [attachment objectForKey:@"proxy_url"];
                    } else {
                        attachmentURL = [attachment objectForKey:@"url"];
                    }


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
                                          stringWithFormat:@"%@%cwidth=%ld&height=%ld", attachmentURL,
                                                           [attachmentURL rangeOfString:@"?"].location == NSNotFound ? '?' : '&',
                                                           (long)width, (long)height]];

                    NSUInteger idx = [newMessage.attachments count];
                    if ([[attachment objectForKey:@"placeholder_version"] integerValue] == 1) {
                        UIImage *img = thumbHashToImage([NSData dataWithBase64EncodedString:[attachment objectForKey:@"placeholder"]]);
                        [newMessage.attachments addObject:[DCTools scaledImageFromImage:img withURL:urlString]];
                    } else {
                        [newMessage.attachments addObject:@[ @(width), @(height) ]];
                    }

                    if (!DCServerCommunicator.sharedInstance.dataSaver) {
                        SDWebImageManager *manager = [SDWebImageManager sharedManager];
                        [manager downloadImageWithURL:urlString
                                              options:SDWebImageCacheMemoryOnly
                                             progress:nil
                                            completed:^(UIImage *retrievedImage, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                                @autoreleasepool {
                                                    if (!retrievedImage || !finished) {
                                                        NSLog(@"Failed to load image with URL %@: %@", urlString, error);
                                                        return;
                                                    }
                                                    [newMessage.attachments replaceObjectAtIndex:idx withObject:[DCTools scaledImageFromImage:retrievedImage withURL:urlString]];
                                                    dispatch_async(
                                                        dispatch_get_main_queue(),
                                                        ^{
                                                            [NSNotificationCenter.defaultCenter
                                                                postNotificationName:@"RELOAD MESSAGE DATA"
                                                                              object:newMessage];
                                                        }
                                                    );
                                                }
                                            }];
                    }
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
                                                  options:SDWebImageCacheMemoryOnly
                                                 progress:nil
                                                completed:^(UIImage *retrievedImage, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                                    @autoreleasepool {
                                                        if (!retrievedImage || !finished
                                                            || !video || !video.thumbnail
                                                            || ![video.thumbnail isKindOfClass:[UIImageView class]]) {
                                                            NSLog(@"Failed to load video thumbnail with URL %@: %@", imageURL, error);
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

                        video.layer.cornerRadius     = 6;
                        video.layer.masksToBounds    = YES;
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
        //});

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
                if (![DCServerCommunicator.sharedInstance.loadedUsers
                        objectForKey:[mention objectForKey:@"id"]]) {
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

                DCUser *user = [DCServerCommunicator.sharedInstance.loadedUsers
                    objectForKey:mentionSnowflake];

                DCRole *role = [DCServerCommunicator.sharedInstance.loadedRoles
                    objectForKey:mentionSnowflake];

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
                NSString *timestamp   = [newMessage.content substringWithRange:[embeddedMention rangeAtIndex:1]];
                NSString *format      = [newMessage.content substringWithRange:[embeddedMention rangeAtIndex:2]];
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

        if (newMessage.editedTimestamp != nil) {
            content = [content stringByAppendingString:@" (edited)"];
        }

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
                                            withString:@"\u00A0\u00A0\u00A0\u00A0\u200B"];
                DCEmoji *emoji = [DCServerCommunicator.sharedInstance.loadedEmojis objectForKey:emojiID];
                if (!emoji) {
                    emoji           = [DCEmoji new];
                    emoji.name      = emojiName;
                    emoji.snowflake = emojiID;
                    emoji.animated  = isAnimated;
                    [DCServerCommunicator.sharedInstance.loadedEmojis
                        setObject:emoji
                           forKey:emoji.snowflake];
                }
                if (emoji && !emoji.image) {
                    emoji.image                = [UIImage new];
                    NSURL *emojiURL            = [NSURL URLWithString:[NSString
                                                               stringWithFormat:@"https://cdn.discordapp.com/emojis/%@.%@?size=32",
                                                                                emoji.snowflake,
                                                                                emoji.animated ? @"gif" : @"png"]];
                    SDWebImageManager *manager = [SDWebImageManager sharedManager];
                    [manager downloadImageWithURL:emojiURL
                                          options:0
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

        CGSize authorNameSize = [newMessage.author.globalName
                 sizeWithFont:[UIFont boldSystemFontOfSize:15]
            constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                lineBreakMode:(NSLineBreakMode)UILineBreakModeWordWrap];
        CGSize contentSize    = [newMessage.content
                 sizeWithFont:[UIFont systemFontOfSize:14]
            constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                lineBreakMode:(NSLineBreakMode)UILineBreakModeWordWrap];

        newMessage.attributedContent = nil;
        if (VERSION_MIN(@"6.0") && [newMessage.content length] > 0) {
            static dispatch_once_t onceToken;
            static TSMarkdownParser *parser;
            dispatch_once(&onceToken, ^{
                parser = [TSMarkdownParser standardParser];
            });
            NSAttributedString *attributedText =
                [parser attributedStringFromMarkdown:newMessage.content];
            if (attributedText && ![attributedText.string isEqualToString:newMessage.content]) {
                contentSize = [attributedText boundingRectWithSize:CGSizeMake(contentWidth, CGFLOAT_MAX)
                                                           options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                           context:nil]
                                  .size;
                newMessage.attributedContent = attributedText;
                newMessage.content = attributedText.string;
                // recalc emoji positions
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
                        // fix position
                        [newMessage.emojis replaceObjectAtIndex:idx withObject:@[ emoji, @(found.location) ]];
                    }
                    range.location = found.location + found.length;
                    range.length = newMessage.content.length - range.location;
                }
            }
        }

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
        newMessage.contentHeight = (cond ? authorNameSize.height : 0)
            + (newMessage.attachmentCount ? contentSize.height : MAX(contentSize.height, 18))
            + 10
            + (newMessage.referencedMessage != nil ? 16 : 0);
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
#warning TODO: do permissions for @everyone
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
            // DBGLOG(@"[READY] Merged member: %@", member);
            if ([[member objectForKey:@"user_id"] isEqualToString:DCServerCommunicator.sharedInstance.snowflake]) {
                [newGuild.userRoles addObjectsFromArray:[member objectForKey:@"roles"]];
            }
        }
    } else {
        for (NSDictionary *member in [jsonGuild objectForKey:@"members"]) {
            // GUILD_CREATE
            [DCServerCommunicator.sharedInstance.loadedUsers
                setObject:[DCTools convertJsonUser:[member objectForKey:@"user"]
                                             cache:true]
                   forKey:[member valueForKeyPath:@"user.id"]];
            if ([[member valueForKeyPath:@"user.id"] isEqualToString:DCServerCommunicator.sharedInstance.snowflake]) {
                [newGuild.userRoles addObjectsFromArray:[member objectForKey:@"roles"]];
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
                              options:0
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
                              options:0
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
            } else if (allowCode == 0 || allowCode == 2 || allowCode == 4 ||
                       [[jsonGuild objectForKey:@"owner_id"] isEqualToString:
                                                                 DCServerCommunicator.sharedInstance.snowflake]) {
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
                emoji = [DCServerCommunicator.sharedInstance.loadedEmojis.allValues
                            filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DCEmoji *obj, NSDictionary *bindings) {
                                return [obj.name isEqualToString:emojiName];
                            }]]
                            .firstObject;
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
                id obj = [DCServerCommunicator.sharedInstance.loadedUsers.allValues
                             filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DCUser *obj, NSDictionary *bindings) {
                                 return [obj.username isEqualToString:mentionName] || [obj.globalName isEqualToString:mentionName];
                             }]]
                             .firstObject;
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

+ (void)joinGuild:(NSString *)inviteCode {
    // dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0),
    // ^{
    NSURL *guildURL = [NSURL
        URLWithString:[NSString stringWithFormat:
                                    @"https://discordapp.com/api/v9/invite/%@",
                                    inviteCode]];

    NSMutableURLRequest *urlRequest = [NSMutableURLRequest
         requestWithURL:guildURL
            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
        timeoutInterval:15];
    [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];

    urlRequest.HTTPMethod = @"POST";

    //[urlRequest setHTTPBody:[NSData dataWithBytes:[messageString UTF8String]
    // length:[messageString length]]];
    [urlRequest addValue:DCServerCommunicator.sharedInstance.token
        forHTTPHeaderField:@"Authorization"];
    [urlRequest addValue:@"application/json"
        forHTTPHeaderField:@"Content-Type"];

    /*NSError *error = nil;
     NSHTTPURLResponse *responseCode = nil;
     int attempts = 0;
     while (attempts == 0 || (attempts <= 10 && error.code ==
     NSURLErrorTimedOut)) { attempts++; error = nil; [UIApplication
     sharedApplication].networkActivityIndicatorVisible++; [DCTools
     checkData:[NSURLConnection sendSynchronousRequest:urlRequest
     returningResponse:&responseCode error:&error] withError:error];
     [UIApplication sharedApplication].networkActivityIndicatorVisible--;*/
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    });
    [NSURLConnection
        sendAsynchronousRequest:urlRequest
                          queue:[NSOperationQueue currentQueue]
              completionHandler:^(
                  NSURLResponse *response, NSData *data, NSError *connError
              ) {
                  dispatch_sync(dispatch_get_main_queue(), ^{
                      [UIApplication sharedApplication]
                          .networkActivityIndicatorVisible = NO;
                  });
              }];
    //}
    //});
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
