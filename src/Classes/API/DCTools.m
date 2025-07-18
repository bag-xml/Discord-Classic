//
//  DCWebImageOperations.m
//  Discord Classic
//
//  Created by bag.xml on 3/17/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import "DCTools.h"
#include <Foundation/NSObjCRuntime.h>
#include <objc/NSObjCRuntime.h>
#include "TSMarkdownParser.h"
#include <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#import "DCChatVideoAttachment.h"
#import "DCMessage.h"
#import "DCRole.h"
#import "DCServerCommunicator.h"
#import "DCUser.h"
#import "QuickLook/QuickLook.h"
#import "UIImage+animatedGIF.h"
#import "NSString+Emojize.h"

// https://discord.gg/X4NSsMC

@implementation DCTools
#define MAX_IMAGE_THREADS 3
static NSInteger threadQueue = 0;

static NSCache *imageCache;
static NSMutableDictionary *pendingBlocks;

static Boolean initializedDispatchQueues = NO;
static dispatch_queue_t dispatchQueues[MAX_IMAGE_THREADS];

+ (void)processImageDataWithURLString:(NSString *)urlString
                             andBlock:(void (^)(UIImage *imageData))processImage {
    NSURL *url = [NSURL URLWithString:urlString];

    if (url == nil) {
        // #ifdef DEBUG
        //         NSLog(@"processImageDataWithURLString: URL: %@. Ignoring...", urlString);
        // #endif
        processImage(nil);
        return;
    }

    if (!imageCache) {
#ifdef DEBUG
        NSLog(@"Creating image cache");
#endif
        imageCache = [[NSCache alloc] init];
    }

    if (!pendingBlocks) {
        pendingBlocks = [[NSMutableDictionary alloc] init];
    }

    if (!initializedDispatchQueues) {
        initializedDispatchQueues = YES;
        for (int i = 0; i < MAX_IMAGE_THREADS; i++) {
            dispatchQueues[i] = dispatch_queue_create(
                [[NSString stringWithFormat:@"Image Thread no. %i", i]
                    UTF8String],
                DISPATCH_QUEUE_SERIAL
            );
            // id object = (__bridge id)queue;
            //[dispatchQueues addObject: object];
        }
    }

    UIImage *image = [imageCache objectForKey:[url absoluteString]];

    if (image) {
        // #ifdef DEBUG
        //         NSLog(@"Image %@ exists in cache", [url absoluteString]);
        // #endif
        processImage(image);
        return;
    } else {
        // #ifdef DEBUG
        //         NSLog(@"Image %@ doesn't exist in cache", [url absoluteString]);
        // #endif
    }

    @synchronized(pendingBlocks) {
        NSMutableArray *blocks = pendingBlocks[[url absoluteString]];
        if (blocks) {
            // Already loading this image, queue up the callback
            [blocks addObject:[processImage copy]];
            return;
        } else {
            // No thread is currently loading this image, start loading
            pendingBlocks[[url absoluteString]] = [NSMutableArray arrayWithObject:[processImage copy]];
        }
    }

    dispatch_queue_t callerQueue = dispatchQueues[threadQueue];
    //(__bridge dispatch_queue_t)(dispatchQueues[threadQueue]);
    // dispatch_get_current_queue();
    threadQueue = (threadQueue + 1) % MAX_IMAGE_THREADS;

    dispatch_async(callerQueue, ^{
        // #ifdef DEBUG
        //         NSLog(@"Image not cached!");
        // #endif
        NSURLResponse *urlResponse;
        NSError *error;
        NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:url
                                                                  cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                              timeoutInterval:15];
        NSData *imageData               = [NSURLConnection sendSynchronousRequest:urlRequest
                                                  returningResponse:&urlResponse
                                                              error:&error];
        __block UIImage *fetchedImage   = nil;

        if (imageData) {
            uint8_t c;
            [imageData getBytes:&c length:1];
            fetchedImage = c == 'G'
                ? [UIImage animatedImageWithAnimatedGIFData:imageData]
                : [UIImage imageWithData:imageData];
            [imageCache
                setObject:fetchedImage ? fetchedImage : [NSNull null]
                   forKey:[url absoluteString]];
            // #ifdef DEBUG
            //             NSLog(@"Image %@ loaded and cached", [url absoluteString]);
            // #endif
        } else {
#ifdef DEBUG
            NSLog(@"Failed to load image from URL %@", [url absoluteString]);
#endif
            [imageCache setObject:[NSNull null]
                           forKey:[url absoluteString]];
        }

        // Execute all waiting blocks
        NSArray *waitingBlocks;
        @synchronized(pendingBlocks) {
            waitingBlocks = pendingBlocks[[url absoluteString]];
            [pendingBlocks removeObjectForKey:[url absoluteString]];
        }
        for (void (^block)(UIImage *) in waitingBlocks) {
            block(fetchedImage);
        }
    });
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
+ (DCUser *)convertJsonUser:(NSDictionary *)jsonUser cache:(bool)cache {
    // NSLog(@"%@", jsonUser);
    DCUser *newUser    = DCUser.new;
    newUser.username   = [jsonUser objectForKey:@"username"];
    newUser.globalName = newUser.username;
    @try {
        if ([jsonUser objectForKey:@"global_name"] &&
            [[jsonUser objectForKey:@"global_name"]
                isKindOfClass:[NSString class]]) {
            newUser.globalName = [jsonUser objectForKey:@"global_name"];
        }
    } @catch (NSException *e) {
    }
    newUser.snowflake = [jsonUser objectForKey:@"id"];

    // Load profile image
    NSString *avatarURL =
        [NSString stringWithFormat:
                      @"https://cdn.discordapp.com/avatars/%@/%@.png?size=80",
                      newUser.snowflake, [jsonUser objectForKey:@"avatar"]];
    [DCTools
        processImageDataWithURLString:avatarURL
                             andBlock:^(UIImage *imageData) {
                                 UIImage *retrievedImage = imageData;

                                 if (imageData) {
                                     newUser.profileImage = retrievedImage;
                                     dispatch_async(
                                         dispatch_get_main_queue(),
                                         ^{
                                             [NSNotificationCenter.defaultCenter
                                                 postNotificationName:
                                                     @"RELOAD USER DATA"
                                                               object:newUser];
                                         }
                                     );
                                 } else {
                                     int selector = 0;
                                     NSNumber *discriminator = @([[jsonUser objectForKey:@"discriminator"] integerValue]);

                                     if ([discriminator integerValue] == 0) {
                                         NSNumber *longId = @([newUser.snowflake longLongValue]);

                                         selector =
                                             (int)(([longId longLongValue] >> 22
                                                   )
                                                   % 6);
                                     } else {
                                         selector =
                                             (int)([discriminator integerValue]
                                                   % 5);
                                     }
                                     newUser.profileImage = [DCUser defaultAvatars][selector];
                                 }
                             }];

    NSString *avatarDecorationURL = [NSString
        stringWithFormat:
            @"https://cdn.discordapp.com/avatar-decoration-presets/"
            @"%@.png?size=96&passthrough=false",
            [jsonUser valueForKeyPath:@"avatar_decoration_data.asset"]];
    [DCTools
        processImageDataWithURLString:avatarDecorationURL
                             andBlock:^(UIImage *imageData) {
                                 UIImage *retrievedImage = imageData;

                                 if (retrievedImage != nil) {
                                     newUser.avatarDecoration = retrievedImage;
                                     dispatch_async(
                                         dispatch_get_main_queue(),
                                         ^{
                                             [NSNotificationCenter.defaultCenter
                                                 postNotificationName:
                                                     @"RELOAD USER DATA"
                                                               object:newUser];
                                         }
                                     );
                                 }
                             }];

    // Save to DCServerCommunicator.loadedUsers
    if (cache) {
        [DCServerCommunicator.sharedInstance.loadedUsers
            setValue:newUser
              forKey:newUser.snowflake];
    }

    return newUser;
}


// Converts an NSDictionary created from json representing a role into a DCRole
// object Also keeps the role in DCServerCommunicator.loadedUsers if cache:YES
+ (DCRole *)convertJsonRole:(NSDictionary *)jsonRole cache:(bool)cache {
    // NSLog(@"%@", jsonUser);
    DCRole *newRole   = DCRole.new;
    newRole.snowflake = [jsonRole objectForKey:@"id"];
    newRole.name      = [jsonRole objectForKey:@"name"];
    newRole.color     = [[jsonRole objectForKey:@"color"] intValue];
    newRole.hoist     = [[jsonRole objectForKey:@"hoist"] boolValue];
    NSString *icon    = [jsonRole objectForKey:@"icon"]; // can be nil
    if (icon != nil && ![icon isKindOfClass:[NSNull class]]) {
        NSString *iconURL = [NSString
            stringWithFormat:
                @"https://cdn.discordapp.com/role-icons/%@/%@.png?size=80",
                newRole.snowflake, icon];
        [DCTools
            processImageDataWithURLString:iconURL
                                 andBlock:^(UIImage *imageData) {
                                     UIImage *retrievedImage = imageData;

                                     if (retrievedImage) {
                                         newRole.icon = retrievedImage;
                                        //  dispatch_async(
                                        //      dispatch_get_main_queue(),
                                        //      ^{
                                        //          [NSNotificationCenter
                                        //                  .defaultCenter
                                        //              postNotificationName:
                                        //                  @"RELOAD CHAT DATA"
                                        //                            object:nil];
                                        //      }
                                        //  );
                                     }
                                 }];
    } else {
        newRole.icon = nil;
    }
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


// Converts an NSDictionary created from json representing a message into a
// message object
+ (DCMessage *)convertJsonMessage:(NSDictionary *)jsonMessage {
    DCMessage *newMessage = DCMessage.new;
    NSDictionary *author  = [jsonMessage objectForKey:@"author"];
    NSString *authorId    = author ? [author objectForKey:@"id"] : nil;

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

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat       = @"yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ";
    [dateFormatter
        setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];

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

    NSDateFormatter *prettyDateFormatter = [NSDateFormatter new];

    prettyDateFormatter.dateStyle = NSDateFormatterShortStyle;
    prettyDateFormatter.timeStyle = NSDateFormatterShortStyle;

    prettyDateFormatter.doesRelativeDateFormatting = YES;

    newMessage.prettyTimestamp =
        [prettyDateFormatter stringFromDate:newMessage.timestamp];
    // dispatch_sync(dispatch_get_main_queue(), ^{
    // Load embeded images from both links and attatchments
    NSArray *embeds = [jsonMessage objectForKey:@"embeds"];
    if (embeds) {
        for (NSDictionary *embed in embeds) {
            NSString *embedType = [embed objectForKey:@"type"];
            if ([embedType isEqualToString:@"image"]) {
                newMessage.attachmentCount++;

                NSString *attachmentURL = nil;

                if ([embed valueForKeyPath:@"image.proxy_url"] != nil) {
                    attachmentURL = [[embed valueForKeyPath:@"image.proxy_url"]
                        stringByReplacingOccurrencesOfString:
                            @"cdn.discordapp.com"
                                                  withString:
                                                      @"media.discordapp.net"];
                } else if ([embed valueForKeyPath:@"image.url"] != nil) {
                    attachmentURL = [[embed valueForKeyPath:@"image.url"]
                        stringByReplacingOccurrencesOfString:
                            @"cdn.discordapp.com"
                                                  withString:
                                                      @"media.discordapp.net"];
                } else {
                    attachmentURL = [[embed objectForKey:@"url"]
                        stringByReplacingOccurrencesOfString:@"cdn.discordapp.com"
                                                  withString:
                                                      @"media.discordapp.net"];
                }

                NSInteger width =
                    [[embed valueForKeyPath:@"image.width"] integerValue];
                NSInteger height =
                    [[embed valueForKeyPath:@"image.height"] integerValue];
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

                NSString *urlString = attachmentURL;

                if (width != 0 || height != 0) {
                    if ([urlString rangeOfString:@"?"].location == NSNotFound) {
                        urlString = [NSString
                            stringWithFormat:@"%@?width=%d&height=%d",
                                             urlString, width, height];
                    } else {
                        urlString = [NSString
                            stringWithFormat:@"%@&width=%d&height=%d",
                                             urlString, width, height];
                    }
                }


                [DCTools
                    processImageDataWithURLString:urlString
                                         andBlock:^(UIImage *imageData) {
                                             UIImage *retrievedImage =
                                                 imageData;

                                             if (retrievedImage != nil) {
                                                 [newMessage.attachments
                                                     addObject:retrievedImage];
                                                 
                                                 dispatch_async(
                                                     dispatch_get_main_queue(),
                                                     ^{
                                                         [NSNotificationCenter
                                                                 .defaultCenter
                                                             postNotificationName:
                                                                 @"RELOAD MESSAGE DATA"
                                                                           object:newMessage];
                                                     }
                                                 );
                                             }
                                         }];
            } else if ([embedType isEqualToString:@"video"] ||
                       [embedType isEqualToString:@"gifv"]) {
                NSURL *attachmentURL = nil;

                if ([embed valueForKeyPath:@"video.proxy_url"] != nil &&
                    [[embed valueForKeyPath:@"video.proxy_url"]
                        isKindOfClass:[NSString class]]) {
                    attachmentURL = [NSURL
                        URLWithString:[embed valueForKeyPath:@"video.proxy_url"]];
                } else if ([embed valueForKeyPath:@"video.url"] != nil &&
                           [[embed valueForKeyPath:@"video.url"]
                               isKindOfClass:[NSString class]]) {
                    attachmentURL =
                        [NSURL URLWithString:[embed valueForKeyPath:@"video.url"]];
                } else {
                    attachmentURL = [NSURL URLWithString:[embed objectForKey:@"url"]];
                }

                dispatch_async(dispatch_get_main_queue(), ^{
                    //[newMessage.attachments
                    // addObject:[[MPMoviePlayerViewController alloc]
                    // initWithContentURL:attachmentURL]];
                    DCChatVideoAttachment *video = [[[NSBundle mainBundle]
                        loadNibNamed:@"DCChatVideoAttachment"
                               owner:self
                             options:nil] objectAtIndex:0];

                    video.videoURL = attachmentURL;

                    NSString *baseURL = [[embed objectForKey:@"url"]
                        stringByReplacingOccurrencesOfString:
                            @"cdn.discordapp.com"
                                                  withString:
                                                      @"media.discordapp.net"];


                    if ([embed valueForKeyPath:@"thumbnail.proxy_url"] != nil &&
                        [[embed valueForKeyPath:@"thumbnail.proxy_url"]
                            isKindOfClass:[NSString class]]) {
                        baseURL = [[embed valueForKeyPath:@"thumbnail.proxy_url"]
                            stringByReplacingOccurrencesOfString:
                                @"cdn.discordapp.com"
                                                      withString:
                                                          @"media.discordapp.net"];
                    } else if ([embed valueForKeyPath:@"thumbnail.url"] != nil &&
                               [[embed valueForKeyPath:@"thumbnail.url"]
                                   isKindOfClass:[NSString class]]) {
                        baseURL = [[embed valueForKeyPath:@"thumbnail.url"]
                            stringByReplacingOccurrencesOfString:
                                @"cdn.discordapp.com"
                                                      withString:
                                                          @"media.discordapp.net"];
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

                    NSString *urlString = baseURL;
                    bool isDiscord      = [baseURL
                        hasPrefix:@"https://media.discordapp.net/"];

                    if (isDiscord) {
                        if (width != 0 || height != 0) {
                            if ([urlString rangeOfString:@"?"].location
                                == NSNotFound) {
                                urlString = [NSString
                                    stringWithFormat:
                                        @"%@?format=png&width=%d&height=%d",
                                        urlString, width, height];
                            } else {
                                urlString = [NSString
                                    stringWithFormat:
                                        @"%@&format=png&width=%d&height=%d",
                                        urlString, width, height];
                            }
                        } else {
                            if ([urlString rangeOfString:@"?"].location
                                == NSNotFound) {
                                urlString = [NSString
                                    stringWithFormat:@"%@?format=png", urlString];
                            } else {
                                urlString = [NSString
                                    stringWithFormat:@"%@&format=png", urlString];
                            }
                        }
                    }

                    [DCTools
                        processImageDataWithURLString:urlString
                                             andBlock:^(UIImage *imageData) {
                                                 UIImage *retrievedImage =
                                                     imageData;

                                                 if (retrievedImage != nil &&
                                                     [retrievedImage
                                                         isKindOfClass:
                                                             [UIImage class]]) {
                                                     dispatch_async(
                                                         dispatch_get_main_queue(),
                                                         ^{
                                                             [video.thumbnail
                                                                 setImage:retrievedImage];
                                                             [NSNotificationCenter.defaultCenter
                                                                 postNotificationName:@"RELOAD CHAT DATA"
                                                                               object:newMessage];
                                                         }
                                                     );
                                                 } else {
                                                     // NSLog(@"Failed to load
                                                     // video thumbnail!");
                                                 }
                                             }];

                    video.layer.cornerRadius     = 6;
                    video.layer.masksToBounds    = YES;
                    video.userInteractionEnabled = YES;
                    [newMessage.attachments addObject:video];
                    newMessage.attachmentCount++;
                });
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

                NSString *attachmentURL = [[attachment objectForKey:@"url"]
                    stringByReplacingOccurrencesOfString:@"cdn.discordapp.com"
                                              withString:
                                                  @"media.discordapp.net"];

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

                NSString *urlString = [NSString
                    stringWithFormat:@"%@&width=%ld&height=%ld", attachmentURL,
                                     (long)width, (long)height];
                if ([attachmentURL rangeOfString:@"?"].location == NSNotFound) {
                    urlString =
                        [NSString stringWithFormat:@"%@?width=%ld&height=%ld",
                                                   attachmentURL, (long)width,
                                                   (long)height];
                }


                [DCTools
                    processImageDataWithURLString:urlString
                                         andBlock:^(UIImage *imageData) {
                                             UIImage *retrievedImage =
                                                 imageData;

                                             if (retrievedImage != nil) {
                                                 [newMessage.attachments
                                                     addObject:retrievedImage];
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
                    DCChatVideoAttachment *video = [[[NSBundle mainBundle]
                        loadNibNamed:@"DCChatVideoAttachment"
                               owner:self
                             options:nil] objectAtIndex:0];

                    video.videoURL = attachmentURL;

                    NSString *baseURL = [[attachment objectForKey:@"url"]
                        stringByReplacingOccurrencesOfString:
                            @"cdn.discordapp.com"
                                                  withString:
                                                      @"media.discordapp.net"];

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


                    NSString *urlString = [NSString
                        stringWithFormat:@"%@format=png&width=%d&height=%d",
                                         baseURL, width, height];
                    if ([baseURL rangeOfString:@"?"].location == NSNotFound) {
                        urlString =
                            [NSString stringWithFormat:
                                          @"%@?format=png&width=%d&height=%d",
                                          baseURL, width, height];
                    }


                    [DCTools
                        processImageDataWithURLString:urlString
                                             andBlock:^(UIImage *imageData) {
                                                 UIImage *retrievedImage =
                                                     imageData;

                                                 if (!retrievedImage || !video || !video.thumbnail
                                                     || ![retrievedImage isKindOfClass:[UIImage class]]
                                                     || ![video.thumbnail isKindOfClass:[UIImageView class]]) {
#ifdef DEBUG
                                                     NSLog(@"Failed to load video thumbnail!");
#endif
                                                     return;
                                                 }
                                                 dispatch_async(
                                                     dispatch_get_main_queue(),
                                                     ^{
                                                         [video.thumbnail
                                                             setImage:retrievedImage];
                                                         [NSNotificationCenter.defaultCenter
                                                             postNotificationName:@"RELOAD MESSAGE DATA"
                                                                           object:newMessage];
                                                     }
                                                 );
                                             }];

                    video.layer.cornerRadius     = 6;
                    video.layer.masksToBounds    = YES;
                    video.userInteractionEnabled = YES;
                    [newMessage.attachments addObject:video];
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

        NSRegularExpression *regex = [NSRegularExpression
            regularExpressionWithPattern:@"\\<@(.*?)\\>"
                                 options:NSRegularExpressionCaseInsensitive
                                   error:NULL];

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
        NSRegularExpression *regex = [NSRegularExpression
            regularExpressionWithPattern:@"\\<#(.*?)\\>"
                                 options:NSRegularExpressionCaseInsensitive
                                   error:NULL];

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
        NSRegularExpression *regex            = [NSRegularExpression
            regularExpressionWithPattern:@"\\<t:(\\d+)(?::(\\w+))?\\>"
                                 options:NSRegularExpressionCaseInsensitive
                                   error:NULL];
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

    // {
    //     // emotes
    //     NSRegularExpression *regex = [NSRegularExpression
    //         regularExpressionWithPattern:@"\\<a?:(.*?):(\\d+)\\>"
    //                              options:NSRegularExpressionCaseInsensitive
    //                                error:NULL];
    //     NSTextCheckingResult *embeddedMention = [regex
    //         firstMatchInString:newMessage.content
    //                    options:0
    //                      range:NSMakeRange(0, newMessage.content.length)];
    //     while (embeddedMention) {
    //         BOOL isAnimated = [newMessage.content
    //             characterAtIndex:embeddedMention.range.location] == 'a';
    //         NSString *emoteName = [newMessage.content substringWithRange:[embeddedMention rangeAtIndex:1]];
    //         NSString *emoteID   = [newMessage.content substringWithRange:[embeddedMention rangeAtIndex:2]];
    //         //https://cdn.discordapp.com/emojis/%@.png
    //         //newMessage.content = [newMessage.content stringByReplacingCharactersInRange:embeddedMention.range withString:replacement];

            

    //         embeddedMention    = [regex firstMatchInString:newMessage.content options:0 range:NSMakeRange(0, newMessage.content.length)];
    //     }
    // }

    NSString *content = [newMessage.content emojizedString];

    content = [content stringByReplacingOccurrencesOfString:@"\u2122\uFE0F"
                                                 withString:@"™"];
    content = [content stringByReplacingOccurrencesOfString:@"\u00AE\uFE0F"
                                                 withString:@"®"];

    if (newMessage.editedTimestamp != nil) {
        content = [content stringByAppendingString:@" (edited)"];
    }

    newMessage.content = content;

    // Calculate height of content to be used when showing messages in a
    // tableview contentHeight does NOT include height of the embeded images or
    // account for height of a grouped message

    CGSize authorNameSize = [newMessage.author.globalName
             sizeWithFont:[UIFont boldSystemFontOfSize:15]
        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
            lineBreakMode:(NSLineBreakMode)UILineBreakModeWordWrap];
    CGSize contentSize = [newMessage.content
             sizeWithFont:[UIFont systemFontOfSize:14]
        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
            lineBreakMode:(NSLineBreakMode)UILineBreakModeWordWrap];
    
    if (VERSION_MIN(@"6.0") && [newMessage.content length]) {
        TSMarkdownParser *parser = [TSMarkdownParser standardParser];
        NSAttributedString *attributedText =
            [parser attributedStringFromMarkdown:newMessage.content];
        if (attributedText) {
            contentSize = [attributedText boundingRectWithSize:CGSizeMake(contentWidth, CGFLOAT_MAX)
                options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                context:nil].size;
        }
    }

    newMessage.contentHeight = authorNameSize.height
        + (newMessage.attachmentCount ? contentSize.height : MAX(contentSize.height, 18))
        + 10
        + (newMessage.referencedMessage != nil ? 16 : 0);
    newMessage.authorNameWidth = 60 + authorNameSize.width;

    return newMessage;
}


+ (DCGuild *)convertJsonGuild:(NSDictionary *)jsonGuild {
    DCGuild *newGuild  = DCGuild.new;
    newGuild.userRoles = NSMutableArray.new;
    newGuild.roles     = NSMutableDictionary.new;
    newGuild.members   = NSMutableArray.new;

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
    for (NSDictionary *member in [jsonGuild objectForKey:@"members"]) {
        [DCServerCommunicator.sharedInstance.loadedUsers
            setObject:[DCTools convertJsonUser:[member objectForKey:@"user"]
                                       cache:true]
               forKey:[member valueForKeyPath:@"user.id"]];
        if ([[member valueForKeyPath:@"user.id"] isEqualToString:DCServerCommunicator.sharedInstance.snowflake]) {
            [newGuild.userRoles addObjectsFromArray:[member objectForKey:@"roles"]];
        }
    }

    newGuild.name = [jsonGuild objectForKey:@"name"];

    // add new types here.
    newGuild.snowflake = [jsonGuild objectForKey:@"id"];
    newGuild.channels  = NSMutableArray.new;

    NSString *iconURL = [NSString
        stringWithFormat:@"https://cdn.discordapp.com/icons/%@/%@.png?size=80",
                         newGuild.snowflake, [jsonGuild objectForKey:@"icon"]];

    NSString *bannerURL =
        [NSString stringWithFormat:
                      @"https://cdn.discordapp.com/banners/%@/%@.png?size=320",
                      newGuild.snowflake, [jsonGuild objectForKey:@"banner"]];

    NSNumber *longId = @([newGuild.snowflake longLongValue]);

    int selector = (int)(([longId longLongValue] >> 22) % 6);

    newGuild.icon = [DCUser defaultAvatars][selector];
    /*CGSize itemSize = CGSizeMake(40, 40);
     UIGraphicsBeginImageContextWithOptions(itemSize, NO,
     UIScreen.mainScreen.scale); CGRect imageRect = CGRectMake(0.0, 0.0,
     itemSize.width, itemSize.height); [newGuild.icon  drawInRect:imageRect];
     newGuild.icon = UIGraphicsGetImageFromCurrentImageContext();
     UIGraphicsEndImageContext();*/

    [DCTools
        processImageDataWithURLString:iconURL
                             andBlock:^(UIImage *imageData) {
                                 UIImage *icon = imageData;

                                 if (!icon) {
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
                             }];

    [DCTools
        processImageDataWithURLString:bannerURL
                             andBlock:^(UIImage *bannerData) {
                                 UIImage *banner = bannerData;
                                 if (!banner) {
                                    return;
                                 }
                                 newGuild.banner = banner;
                                 dispatch_async(dispatch_get_main_queue(), ^{
                                     UIGraphicsEndImageContext();
                                 });
                             }];


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
        if ([[jsonChannel objectForKey:@"type"] isEqual:@0] || // text channel
            [[jsonChannel objectForKey:@"type"] isEqual:@5] || // announcements
            [[jsonChannel objectForKey:@"type"] isEqual:@4]) { // category
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
            bool canWrite = true;

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
                        if ((deny & SEND_MESSAGES) == SEND_MESSAGES) {
                            canWrite = false;
                        }
                        if ((deny & VIEW_CHANNEL) == VIEW_CHANNEL) {
                            allowCode = 1;
                        }
                        if ((allow & SEND_MESSAGES) == SEND_MESSAGES) {
                            canWrite = true;
                        }
                        if ((allow & VIEW_CHANNEL) == VIEW_CHANNEL) {
                            allowCode = 2;
                        }
                    }
                } else if (type == 1) { // Member overwrite, break on these
                    if ([idValue isEqualToString:
                                    DCServerCommunicator.sharedInstance.snowflake]) {
                        if ((deny & SEND_MESSAGES) == SEND_MESSAGES) {
                            canWrite = false;
                        }
                        if ((deny & VIEW_CHANNEL) == VIEW_CHANNEL) {
                            allowCode = 3;
                        }
                        if ((allow & SEND_MESSAGES) == SEND_MESSAGES) {
                            canWrite = true;
                        }
                        if ((allow & VIEW_CHANNEL) == VIEW_CHANNEL) {
                            allowCode = 4;
                        }
                        break;
                    }
                }
            }

            newChannel.writeable = canWrite || [[jsonGuild objectForKey:@"owner_id"] isEqualToString:
                        DCServerCommunicator.sharedInstance.snowflake];
            // ignore perms for guild categories
            if (newChannel.type == 4) { // category
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
        } else if ([channel1.parentID isKindOfClass:[NSString class]] && [channel2.parentID isKindOfClass:[NSString class]] &&
                   ![channel1.parentID isEqualToString:channel2.parentID]) {
            NSUInteger idx1 = [categories indexOfObjectPassingTest:^BOOL(DCChannel *category, NSUInteger idx, BOOL *stop) {
                return [category.snowflake isEqualToString:channel1.parentID];
            }], idx2 = [categories indexOfObjectPassingTest:^BOOL(DCChannel *category, NSUInteger idx, BOOL *stop) {
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
        
        if (channel1.type < channel2.type) {
            return NSOrderedAscending;
        } else if (channel1.type > channel2.type) {
            return NSOrderedDescending;
        } else if (channel1.position < channel2.position) {
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
            if (channel.type == 4
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

    [urlRequest setHTTPMethod:@"POST"];

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
            [request setURL:randomEndpoint];
            [request setHTTPMethod:@"GET"];
            [request setValue:@"application/json"
                forHTTPHeaderField:@"Content-Type"];
            [request setTimeoutInterval:10];

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
