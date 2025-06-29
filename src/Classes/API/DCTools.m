//
//  DCWebImageOperations.m
//  Discord Classic
//
//  Created by bag.xml on 3/17/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import "DCTools.h"
#include <Foundation/Foundation.h>
#import "DCChatVideoAttachment.h"
#import "DCMessage.h"
#import "DCRole.h"
#import "DCServerCommunicator.h"
#import "DCUser.h"
#import "QuickLook/QuickLook.h"
#import "UIImage+animatedGIF.h"

// https://discord.gg/X4NSsMC

@implementation DCTools
#define MAX_IMAGE_THREADS 3
static NSInteger threadQueue = 0;

static NSCache *imageCache;

static Boolean initializedDispatchQueues = NO;
static dispatch_queue_t dispatchQueues[MAX_IMAGE_THREADS];

+ (void)processImageDataWithURLString:(NSString *)urlString
                             andBlock:(void (^)(UIImage *imageData)
                                      )processImage {
    NSURL *url = [NSURL URLWithString:urlString];

    if (url == nil) {
        // NSLog(@"processImageDataWithURLString: nil URL encountered.
        // Ignoring...");
        processImage(nil);
        return;
    }

    if (!imageCache) {
        // NSLog(@"Creating image cache");
        imageCache = [[NSCache alloc] init];
    }

    if (!initializedDispatchQueues) {
        initializedDispatchQueues = YES;
        for (int i = 0; i < MAX_IMAGE_THREADS; i++) {
            // dispatch_queue_t queue = dispatch_queue_create([[NSString
            // stringWithFormat:@"Image Thread no. %i", i] UTF8String],
            // DISPATCH_QUEUE_SERIAL); id object = (__bridge id)queue;
            //[dispatchQueues addObject: object];
            dispatchQueues[i] = dispatch_queue_create(
                [[NSString stringWithFormat:@"Image Thread no. %i", i]
                    UTF8String],
                DISPATCH_QUEUE_SERIAL
            );
        }
    }

    UIImage *image = [imageCache objectForKey:[url absoluteString]];

    if (image) {
        // NSLog(@"Image %@ exists in cache", [url absoluteString]);
    } else {
        // NSLog(@"Image %@ doesn't exist in cache", [url absoluteString]);
    }

    __block id cacheWait = [imageCache objectForKey:[url absoluteString]];

    if (!image
        || ([cacheWait isKindOfClass:[NSString class]] &&
            [cacheWait isEqualToString:@"l"])) {
        dispatch_queue_t callerQueue = dispatchQueues
            [threadQueue]; //(__bridge
        // dispatch_queue_t)(dispatchQueues[threadQueue]);//dispatch_get_current_queue();
        threadQueue = (threadQueue + 1) % MAX_IMAGE_THREADS;

        dispatch_async(callerQueue, ^{
            // NSData* imageData = [NSData dataWithContentsOfURL:url];
            cacheWait = [imageCache objectForKey:[url absoluteString]];

            while ([cacheWait isKindOfClass:[NSString class]] &&
                   [cacheWait isEqualToString:@"l"]) {
                cacheWait = [imageCache objectForKey:[url absoluteString]];
            }

            __block UIImage *image =
                [imageCache objectForKey:[url absoluteString]];
            if (!image) {
                // NSLog(@"Image not cached!");
                [imageCache setObject:@"l"
                               forKey:[url absoluteString]]; // mark as loading
                NSURLResponse *urlResponse;
                NSError *error;
                NSMutableURLRequest *urlRequest = [NSMutableURLRequest
                     requestWithURL:url
                        cachePolicy:NSURLRequestUseProtocolCachePolicy
                    timeoutInterval:15];
                NSData *imageData =
                    [NSURLConnection sendSynchronousRequest:urlRequest
                                          returningResponse:&urlResponse
                                                      error:&error];
                dispatch_sync(dispatch_get_main_queue(), ^{
                    uint8_t c;
                    [imageData getBytes:&c length:1];
                    if (c == 0x47) {
                        image = [UIImage
                            animatedImageWithAnimatedGIFData:imageData];
                    } else {
                        image = [UIImage imageWithData:imageData];
                    }
                    if (image != nil) {
                        [imageCache setObject:image
                                       forKey:[url absoluteString]];
                    } else {
                        [imageCache setObject:[NSNull alloc]
                                       forKey:[url absoluteString]];
                    }
                    // NSLog(@"Image added to cache");
                });
            }

            if (image == nil || ![image isKindOfClass:[UIImage class]]
                || ![[imageCache objectForKey:[url absoluteString]]
                    isKindOfClass:[UIImage class]]) {
                image = nil;
            }

            dispatch_sync(dispatch_get_main_queue(), ^{
                @try {
                    if ([image isKindOfClass:[UIImage class]]) {
                        processImage(image);
                    }
                } @catch (id e) {
                }
            });
        });
    } else {
        // NSLog(@"Image cached!");
        processImage(image);
    }
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
    newUser.username   = [jsonUser valueForKey:@"username"];
    newUser.globalName = newUser.username;
    @try {
        if ([jsonUser objectForKey:@"global_name"] &&
            [[jsonUser valueForKey:@"global_name"]
                isKindOfClass:[NSString class]]) {
            newUser.globalName = [jsonUser valueForKey:@"global_name"];
        }
    } @catch (NSException *e) {
    }
    newUser.snowflake = [jsonUser valueForKey:@"id"];

    // Load profile image
    NSString *avatarURL =
        [NSString stringWithFormat:
                      @"https://cdn.discordapp.com/avatars/%@/%@.png?size=80",
                      newUser.snowflake, [jsonUser valueForKey:@"avatar"]];
    [DCTools
        processImageDataWithURLString:avatarURL
                             andBlock:^(UIImage *imageData) {
                                 UIImage *retrievedImage = imageData;

                                 if (imageData) {
                                     dispatch_async(
                                         dispatch_get_main_queue(),
                                         ^{
                                             newUser.profileImage =
                                                 retrievedImage;
                                             [NSNotificationCenter.defaultCenter
                                                 postNotificationName:
                                                     @"RELOAD CHAT DATA"
                                                               object:nil];
                                         }
                                     );
                                 } else {
                                     int selector = 0;
                                     NSNumberFormatter *f =
                                         [[NSNumberFormatter alloc] init];
                                     [f setNumberStyle:
                                             NSNumberFormatterDecimalStyle];
                                     NSNumber *discriminator = [f
                                         numberFromString:
                                             [jsonUser
                                                 valueForKey:@"discriminator"]];

                                     if ([discriminator integerValue] == 0) {
                                         NSNumberFormatter *f =
                                             [[NSNumberFormatter alloc] init];
                                         [f setNumberStyle:
                                                 NSNumberFormatterDecimalStyle];
                                         NSNumber *longId = [f
                                             numberFromString:newUser
                                                                  .snowflake];

                                         selector =
                                             (int)(([longId longLongValue] >> 22
                                                   )
                                                   % 6);
                                     } else {
                                         selector =
                                             (int)([discriminator integerValue]
                                                   % 5);
                                     }
                                     newUser.profileImage =
                                         [DCUser defaultAvatars][selector];
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
                                     dispatch_async(
                                         dispatch_get_main_queue(),
                                         ^{
                                             newUser.avatarDecoration =
                                                 retrievedImage;
                                             [NSNotificationCenter.defaultCenter
                                                 postNotificationName:
                                                     @"RELOAD CHAT DATA"
                                                               object:nil];
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
    newRole.snowflake = [jsonRole valueForKey:@"id"];
    newRole.name      = [jsonRole valueForKey:@"name"];
    newRole.color     = [[jsonRole valueForKey:@"color"] intValue];
    newRole.hoist     = [[jsonRole valueForKey:@"hoist"] boolValue];
    NSString *icon    = [jsonRole valueForKey:@"icon"]; // can be nil
    if (icon != nil && ![icon isKindOfClass:[NSNull class]]) {
        NSString *iconURL = [NSString
            stringWithFormat:
                @"https://cdn.discordapp.com/role-icons/%@/%@.png?size=80",
                newRole.snowflake, icon];
        [DCTools
            processImageDataWithURLString:iconURL
                                 andBlock:^(UIImage *imageData) {
                                     UIImage *retrievedImage = imageData;

                                     if (imageData) {
                                         dispatch_async(
                                             dispatch_get_main_queue(),
                                             ^{
                                                 newRole.icon =
                                                     retrievedImage;
                                                 [NSNotificationCenter
                                                         .defaultCenter
                                                     postNotificationName:
                                                         @"RELOAD CHAT DATA"
                                                                   object:nil];
                                             }
                                         );
                                     }
                                 }];
    } else {
        newRole.icon = nil;
    }
    newRole.unicodeEmoji = [jsonRole valueForKey:@"unicode_emoji"]; // can be nil
    newRole.position     = [[jsonRole valueForKey:@"position"] intValue];
    newRole.permissions  = [jsonRole valueForKey:@"permissions"];
    newRole.managed      = [[jsonRole valueForKey:@"managed"] boolValue];
    newRole.mentionable  = [[jsonRole valueForKey:@"mentionable"] boolValue];

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
    if ([[jsonMessage valueForKey:@"referenced_message"]
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
                valueForKey:referencedAuthorId];
        if ([[referencedJsonMessage valueForKey:@"content"]
                isKindOfClass:[NSString class]]) {
            referencedMessage.content =
                [referencedJsonMessage valueForKey:@"content"];
        } else {
            referencedMessage.content = @"";
        }
        referencedMessage.snowflake       = [referencedJsonMessage valueForKey:@"id"];
        CGSize authorNameSize             = [referencedMessage.author.globalName
                 sizeWithFont:[UIFont boldSystemFontOfSize:10]
            constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                lineBreakMode:(NSLineBreakMode)UILineBreakModeWordWrap];
        referencedMessage.authorNameWidth = 80 + authorNameSize.width;

        newMessage.referencedMessage = referencedMessage;
    }

    newMessage.author =
        [DCServerCommunicator.sharedInstance.loadedUsers valueForKey:authorId];

    newMessage.content         = [jsonMessage valueForKey:@"content"];
    newMessage.snowflake       = [jsonMessage valueForKey:@"id"];
    newMessage.attachments     = NSMutableArray.new;
    newMessage.attachmentCount = 0;

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat       = @"yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ";
    [dateFormatter
        setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];

    newMessage.timestamp =
        [dateFormatter dateFromString:[jsonMessage valueForKey:@"timestamp"]];
    if (newMessage.timestamp == nil) {
        dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
        newMessage.timestamp     = [dateFormatter
            dateFromString:[jsonMessage valueForKey:@"timestamp"]];
    }
    if (newMessage.timestamp == nil) {
        // NSLog(@"Invalid timestamp %@", [jsonMessage
        // valueForKey:@"timestamp"]);

        if ([jsonMessage valueForKey:@"edited_timestamp"] != nil) {
            newMessage.editedTimestamp = [dateFormatter
                dateFromString:[jsonMessage valueForKey:@"edited_timestamp"]];
            if (newMessage.editedTimestamp == nil) {
                dateFormatter.dateFormat   = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
                newMessage.editedTimestamp = [dateFormatter
                    dateFromString:[jsonMessage
                                       valueForKey:@"edited_timestamp"]];
            }
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
            NSString *embedType = [embed valueForKey:@"type"];
            if ([embedType isEqualToString:@"image"]) {
                newMessage.attachmentCount++;

                NSString *attachmentURL = [[embed valueForKey:@"url"]
                    stringByReplacingOccurrencesOfString:@"cdn.discordapp.com"
                                              withString:
                                                  @"media.discordapp.net"];

                if ([embed valueForKey:@"image.url"] != nil) {
                    attachmentURL = [[embed valueForKey:@"image.url"]
                        stringByReplacingOccurrencesOfString:
                            @"cdn.discordapp.com"
                                                  withString:
                                                      @"media.discordapp.net"];
                }

                if ([embed valueForKey:@"image.proxy_url"] != nil) {
                    attachmentURL = [[embed valueForKey:@"image.proxy_url"]
                        stringByReplacingOccurrencesOfString:
                            @"cdn.discordapp.com"
                                                  withString:
                                                      @"media.discordapp.net"];
                }

                NSInteger width =
                    [[embed valueForKey:@"image.width"] integerValue];
                NSInteger height =
                    [[embed valueForKey:@"image.height"] integerValue];
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
                                                                 @"RELOAD CHAT DATA"
                                                                           object:
                                                                               nil];
                                                     }
                                                 );
                                             }
                                         }];
            } else if ([embedType isEqualToString:@"video"] ||
                       [embedType isEqualToString:@"gifv"]) {
                newMessage.attachmentCount++;

                NSURL *attachmentURL =
                    [NSURL URLWithString:[embed valueForKey:@"url"]];

                if ([embed valueForKey:@"video.proxy_url"] != nil &&
                    [[embed valueForKey:@"video.proxy_url"]
                        isKindOfClass:[NSString class]]) {
                    attachmentURL = [NSURL
                        URLWithString:[embed valueForKey:@"video.proxy_url"]];
                } else if ([embed valueForKey:@"video.url"] != nil &&
                           [[embed valueForKey:@"video.url"]
                               isKindOfClass:[NSString class]]) {
                    attachmentURL =
                        [NSURL URLWithString:[embed valueForKey:@"video.url"]];
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

                    NSString *baseURL = [[embed valueForKey:@"url"]
                        stringByReplacingOccurrencesOfString:
                            @"cdn.discordapp.com"
                                                  withString:
                                                      @"media.discordapp.net"];


                    if ([embed valueForKey:@"video.proxy_url"] != nil &&
                        [[embed valueForKey:@"video.proxy_url"]
                            isKindOfClass:[NSString class]]) {
                        baseURL = [[embed valueForKey:@"video.proxy_url"]
                            stringByReplacingOccurrencesOfString:
                                @"cdn.discordapp.com"
                                                      withString:
                                                          @"media.discordapp."
                                                          @"net"];
                    } else if ([embed valueForKey:@"video.url"] != nil &&
                               [[embed valueForKey:@"video.url"]
                                   isKindOfClass:[NSString class]]) {
                        baseURL = [[embed valueForKey:@"video.url"]
                            stringByReplacingOccurrencesOfString:
                                @"cdn.discordapp.com"
                                                      withString:
                                                          @"media.discordapp."
                                                          @"net"];
                    }

                    NSInteger width =
                        [[embed valueForKey:@"video.width"] integerValue];
                    NSInteger height =
                        [[embed valueForKey:@"video.height"] integerValue];
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

                    if (width != 0 || height != 0) {
                        if ([urlString rangeOfString:@"?"].location
                            == NSNotFound) {
                            urlString = [NSString
                                stringWithFormat:
                                    @"%@?format=jpeg&width=%d&height=%d",
                                    urlString, width, height];
                        } else {
                            urlString = [NSString
                                stringWithFormat:
                                    @"%@&format=jpeg&width=%d&height=%d",
                                    urlString, width, height];
                        }
                    } else {
                        if ([urlString rangeOfString:@"?"].location
                            == NSNotFound) {
                            urlString = [NSString
                                stringWithFormat:@"%@?format=jpeg", urlString];
                        } else {
                            urlString = [NSString
                                stringWithFormat:@"%@&format=jpeg", urlString];
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
                                                     [video.thumbnail
                                                         setImage:
                                                             retrievedImage];
                                                     dispatch_async(
                                                         dispatch_get_main_queue(
                                                         ),
                                                         ^{
                                                             [NSNotificationCenter
                                                                     .defaultCenter
                                                                 postNotificationName:
                                                                     @"RELOAD CHAT DATA"
                                                                               object:
                                                                                   nil];
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
            NSString *fileType = [attachment valueForKey:@"content_type"];
            if ([fileType rangeOfString:@"image/"].location != NSNotFound) {
                newMessage.attachmentCount++;

                NSString *attachmentURL = [[attachment valueForKey:@"url"]
                    stringByReplacingOccurrencesOfString:@"cdn.discordapp.com"
                                              withString:
                                                  @"media.discordapp.net"];

                NSInteger width =
                    [[attachment valueForKey:@"width"] integerValue];
                NSInteger height =
                    [[attachment valueForKey:@"height"] integerValue];
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
                                                         [NSNotificationCenter
                                                                 .defaultCenter
                                                             postNotificationName:
                                                                 @"RELOAD CHAT DATA"
                                                                           object:
                                                                               nil];
                                                     }
                                                 );
                                             }
                                         }];
            } else if ([fileType rangeOfString:@"video/"].location
                       != NSNotFound) {
                newMessage.attachmentCount++;

                NSURL *attachmentURL =
                    [NSURL URLWithString:[attachment valueForKey:@"url"]];
                dispatch_async(dispatch_get_main_queue(), ^{
                    //[newMessage.attachments
                    // addObject:[[MPMoviePlayerViewController alloc]
                    // initWithContentURL:attachmentURL]];
                    DCChatVideoAttachment *video = [[[NSBundle mainBundle]
                        loadNibNamed:@"DCChatVideoAttachment"
                               owner:self
                             options:nil] objectAtIndex:0];

                    video.videoURL = attachmentURL;

                    NSString *baseURL = [[attachment valueForKey:@"url"]
                        stringByReplacingOccurrencesOfString:
                            @"cdn.discordapp.com"
                                                  withString:
                                                      @"media.discordapp.net"];

                    NSInteger width =
                        [[attachment valueForKey:@"width"] integerValue];
                    NSInteger height =
                        [[attachment valueForKey:@"height"] integerValue];
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
                        stringWithFormat:@"%@format=jpeg&width=%d&height=%d",
                                         baseURL, width, height];
                    if ([baseURL rangeOfString:@"?"].location == NSNotFound) {
                        urlString =
                            [NSString stringWithFormat:
                                          @"%@?format=jpeg&width=%d&height=%d",
                                          baseURL, width, height];
                    }


                    [DCTools
                        processImageDataWithURLString:urlString
                                             andBlock:^(UIImage *imageData) {
                                                 UIImage *retrievedImage =
                                                     imageData;

                                                 if (retrievedImage != nil) {
                                                     [video.thumbnail
                                                         setImage:retrievedImage];
                                                     dispatch_async(
                                                         dispatch_get_main_queue(
                                                         ),
                                                         ^{
                                                             [NSNotificationCenter.defaultCenter
                                                                 postNotificationName:
                                                                     @"RELOAD CHAT DATA"
                                                                               object:nil];
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
                });
            } else {
                // NSLog(@"unknown attachment type %@", fileType);
                newMessage.content =
                    [NSString stringWithFormat:@"%@\n%@", newMessage.content,
                                               [attachment valueForKey:@"url"]];
                continue;
            }
        }
    }
    //});

    // Parse in-text mentions into readable @<username>
    NSArray *mentions     = [jsonMessage objectForKey:@"mentions"];
    NSArray *mentionRoles = [jsonMessage objectForKey:@"mention_roles"];

    if ([[jsonMessage valueForKey:@"mention_everyone"] boolValue]) {
        newMessage.pingingUser = true;
    }

    if (mentions.count || mentionRoles.count) {
        for (NSDictionary *mention in mentions) {
            if ([[mention valueForKey:@"id"] isEqualToString:
                    DCServerCommunicator.sharedInstance.snowflake]) {
                newMessage.pingingUser = true;
            }
            if (![DCServerCommunicator.sharedInstance.loadedUsers
                    valueForKey:[mention valueForKey:@"id"]]) {
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
                valueForKey:mentionSnowflake];

            DCRole *role = [DCServerCommunicator.sharedInstance.loadedRoles
                valueForKey:mentionSnowflake];

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
            DCChannel *channel = [DCServerCommunicator.sharedInstance.channels objectForKey:channelSnowflake];
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
    newGuild.members   = NSMutableArray.new;
    newGuild.roles     = NSMutableDictionary.new;

    // Get @everyone role
    for (NSDictionary *guildRole in [jsonGuild objectForKey:@"roles"]) {
        if ([[guildRole valueForKey:@"name"] isEqualToString:@"@everyone"]) {
#warning TODO: do permissions for @everyone
            [newGuild.userRoles addObject:[guildRole valueForKey:@"id"]];
        }
        [newGuild.roles
            setObject:[DCTools convertJsonRole:guildRole cache:true]
               forKey:[guildRole valueForKey:@"id"]];
    }

    // Get roles of the current user
    for (NSDictionary *member in [jsonGuild objectForKey:@"members"]) {
        [newGuild.members
            addObject:[DCTools convertJsonUser:[member valueForKey:@"user"] cache:true]];
        if ([[member valueForKeyPath:@"user.id"] isEqualToString:DCServerCommunicator.sharedInstance.snowflake]) {
            [newGuild.userRoles addObjectsFromArray:[member valueForKey:@"roles"]];
        }
    }

    newGuild.name = [jsonGuild valueForKey:@"name"];

    // add new types here.
    newGuild.snowflake = [jsonGuild valueForKey:@"id"];
    newGuild.channels  = NSMutableArray.new;

    NSString *iconURL = [NSString
        stringWithFormat:@"https://cdn.discordapp.com/icons/%@/%@.png?size=80",
                         newGuild.snowflake, [jsonGuild valueForKey:@"icon"]];

    NSString *bannerURL =
        [NSString stringWithFormat:
                      @"https://cdn.discordapp.com/banners/%@/%@.png?size=320",
                      newGuild.snowflake, [jsonGuild valueForKey:@"banner"]];

    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    [f setNumberStyle:NSNumberFormatterDecimalStyle];
    NSNumber *longId = [f numberFromString:newGuild.snowflake];

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

                                 if (icon != nil) {
                                     newGuild.icon   = icon;
                                     CGSize itemSize = CGSizeMake(40, 40);
                                     UIGraphicsBeginImageContextWithOptions(
                                         itemSize, NO, UIScreen.mainScreen.scale
                                     );
                                     CGRect imageRect = CGRectMake(
                                         0.0, 0.0, itemSize.width,
                                         itemSize.height
                                     );
                                     [newGuild.icon drawInRect:imageRect];
                                     newGuild.icon =
                                         UIGraphicsGetImageFromCurrentImageContext(
                                         );
                                     UIGraphicsEndImageContext();
                                 }
                             }];

    [DCTools
        processImageDataWithURLString:bannerURL
                             andBlock:^(UIImage *bannerData) {
                                 UIImage *banner = bannerData;
                                 if (banner != nil) {
                                     newGuild.banner = banner;
                                     UIGraphicsEndImageContext();
                                 }

                                 dispatch_async(dispatch_get_main_queue(), ^{
                                     [NSNotificationCenter.defaultCenter
                                         postNotificationName:@"RELOAD GUILD LIST"
                                                       object:DCServerCommunicator.sharedInstance];
                                 });
                             }];


    NSMutableArray *categories = NSMutableArray.new;

    NSArray *combined = [[jsonGuild valueForKey:@"channels"] arrayByAddingObjectsFromArray:[jsonGuild valueForKey:@"threads"]];
    for (NSDictionary *jsonChannel in combined) {
        // regardless of implementation or permissions, add to channels list so they're visible in <#snowflake>
        DCChannel *newChannel = DCChannel.new;

        newChannel.snowflake = [jsonChannel valueForKey:@"id"];
        newChannel.parentID  = [jsonChannel valueForKey:@"parent_id"];
        newChannel.name      = [jsonChannel valueForKey:@"name"];
        newChannel.lastMessageId =
            [jsonChannel valueForKey:@"last_message_id"];
        newChannel.parentGuild = newGuild;
        newChannel.type        = [[jsonChannel valueForKey:@"type"] intValue];
        NSString *rawPosition  = [jsonChannel valueForKey:@"position"];
        newChannel.position    = rawPosition ? [rawPosition intValue] : 0;

        // check if channel is muted
        if ([DCServerCommunicator.sharedInstance.userChannelSettings
                objectForKey:newChannel.snowflake]) {
            newChannel.muted = true;
        }

        [DCServerCommunicator.sharedInstance.channels
            setObject:newChannel
               forKey:newChannel.snowflake];

        // Make sure jsonChannel is a text channel or a category
        // we dont want to include voice channels in the text channel list
        if ([[jsonChannel valueForKey:@"type"] isEqual:@0] || // text channel
            [[jsonChannel valueForKey:@"type"] isEqual:@5] || // announcements
            [[jsonChannel valueForKey:@"type"] isEqual:@4]) { // category
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

            // Calculate permissions
            NSArray *rawOverwrites =
                [jsonChannel objectForKey:@"permission_overwrites"];
            // sort with role priority
            NSArray *overwrites = [rawOverwrites sortedArrayUsingComparator:
                ^NSComparisonResult(NSDictionary *perm1, NSDictionary *perm2) {
                    DCRole *role1 = [newGuild.roles valueForKey:[perm1 valueForKey:@"id"]];
                    DCRole *role2 = [newGuild.roles valueForKey:[perm2 valueForKey:@"id"]];
                    return role1.position < role2.position ? NSOrderedAscending : NSOrderedDescending;
                }
            ];
            for (NSDictionary *permission in overwrites) {
                uint64_t type     = [[permission valueForKey:@"type"] longLongValue];
                NSString *idValue = [permission valueForKey:@"id"];
                uint64_t deny     = [[permission valueForKey:@"deny"] longLongValue];
                uint64_t allow    = [[permission valueForKey:@"allow"] longLongValue];

                if (type == 0) { // Role overwrite
                    if ([newGuild.userRoles containsObject:idValue]) {
                        if ((deny & VIEW_CHANNEL) == VIEW_CHANNEL) {
                            allowCode = 1;
                        }
                        if ((allow & VIEW_CHANNEL) == VIEW_CHANNEL) {
                            allowCode = 2;
                        }
                    }
                } else if (type == 1) { // Member overwrite, break on these
                    if ([idValue isEqualToString:
                                     DCServerCommunicator.sharedInstance.snowflake]) {
                        if ((deny & VIEW_CHANNEL) == VIEW_CHANNEL) {
                            allowCode = 3;
                            break;
                        }
                        if ((allow & VIEW_CHANNEL) == VIEW_CHANNEL) {
                            allowCode = 4;
                            break;
                        }
                    }
                }
            }

            if (allowCode == 0 || allowCode == 2 || allowCode == 4 ||
                [[jsonGuild valueForKey:@"owner_id"] isEqualToString:
                                                         DCServerCommunicator.sharedInstance.snowflake]) {

                if (newChannel.type == 4) { // category
                    [categories addObject:newChannel];
                } else {
                    [newGuild.channels addObject:newChannel];
                }
            }
        }
    }

    [newGuild.channels sortUsingComparator:^NSComparisonResult(
                           DCChannel *channel1, DCChannel *channel2
    ) {
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
            if (channel.type == 4 
            || channel.parentID == nil 
            || (NSNull*)channel.parentID == [NSNull null]
            ) {
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
