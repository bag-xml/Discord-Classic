//
//  DCChannel.m
//  Discord Classic
//
//  Created by bag.xml on 3/12/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import "DCChannel.h"
#include <objc/NSObjCRuntime.h>
#include <CoreFoundation/CFBase.h>
#include <Foundation/Foundation.h>
#include "DCChatViewController.h"
#include "DCMessage.h"
#import "DCServerCommunicator.h"
#import "DCTools.h"
#import "NSString+Emojize.h"

@interface DCChannel ()

@property NSURLConnection *connection;

@end

@implementation DCChannel
@synthesize users;

static dispatch_queue_t channel_event_queue;
- (dispatch_queue_t)get_channel_event_queue {
    if (channel_event_queue == nil) {
        channel_event_queue = dispatch_queue_create(
            [@"Discord::API::Channel::Event" UTF8String],
            DISPATCH_QUEUE_CONCURRENT
        );
    }
    return channel_event_queue;
}

static dispatch_queue_t channel_send_queue;
- (dispatch_queue_t)get_channel_send_queue {
    if (channel_send_queue == nil) {
        channel_send_queue = dispatch_queue_create(
            [@"Discord::API::Channel::Send" UTF8String], DISPATCH_QUEUE_SERIAL
        );
    }
    return channel_send_queue;
}

- (NSString *)description {
    return
        [NSString stringWithFormat:
                      @"[Channel] Snowflake: %@, Type: %li, Read: %d, Name: %@",
                      self.snowflake, (long)self.type, self.unread, self.name];
}

- (void)checkIfRead {
    DCChannel *parentChannel = [DCServerCommunicator.sharedInstance.channels objectForKey:self.parentID];
    self.unread              = (!self.muted && (!parentChannel || ![parentChannel muted]) && self.lastMessageId && self.lastMessageId != (id)NSNull.null && [self.lastMessageId isKindOfClass:[NSString class]] && ![self.lastMessageId isEqualToString:self.lastReadMessageId]);
    [self.parentGuild checkIfRead];
}

// copied straight from https://stackoverflow.com/a/7935625, thanks!
+ (NSString*)escapeUnicodeString:(NSString*)string {
    // lastly escaped quotes and back slash
    // note that the backslash has to be escaped before the quote
    // otherwise it will end up with an extra backslash
    NSString* escapedString = [string stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escapedString = [escapedString stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];

    // convert to encoded unicode
    // do this by getting the data for the string
    // in UTF16 little endian (for network byte order)
    NSData* data = [escapedString dataUsingEncoding:NSUTF16LittleEndianStringEncoding allowLossyConversion:YES];
    size_t bytesRead = 0;
    const char* bytes = data.bytes;
    NSMutableString* encodedString = [NSMutableString string];

    // loop through the byte array
    // read two bytes at a time, if the bytes
    // are above a certain value they are unicode
    // otherwise the bytes are ASCII characters
    // the %C format will write the character value of bytes
    while (bytesRead < data.length)
    {
        uint16_t code = *((uint16_t*) &bytes[bytesRead]);
        if (code > 0x007E)
        {
            [encodedString appendFormat:@"\\u%04X", code];
        }
        else
        {
            [encodedString appendFormat:@"%C", code];
        }
        bytesRead += sizeof(uint16_t);
    }

    // done
    return encodedString;
}

- (void)sendMessage:(NSString *)message
    referencingMessage:(DCMessage *)referencedMessage
           disablePing:(BOOL)disablePing {
    dispatch_async([self get_channel_send_queue], ^{
        NSURL *channelURL = [NSURL
            URLWithString:[NSString
                              stringWithFormat:@"https://discordapp.com/api/v9/channels/%@/messages",
                                               self.snowflake]];

        NSMutableURLRequest *urlRequest = [NSMutableURLRequest
             requestWithURL:channelURL
                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
            timeoutInterval:10];
        [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];

        // NSString *escapedMessage = [message emojizedString];
        NSString *escapedMessage = message;
        CFStringRef transform = CFSTR("Any-Hex/Java");
        CFStringTransform((__bridge CFMutableStringRef)escapedMessage, NULL, transform, NO);

        NSMutableDictionary *dictionary = [@{
            @"content" : escapedMessage
        } mutableCopy];

        if (referencedMessage) {
            [dictionary addEntriesFromDictionary:@{
                @"type" : @(DCMessageTypeReply),
                @"message_reference" : @{
                    @"type" : @(DCMessageReferenceTypeDefault),
                    @"message_id" : referencedMessage.snowflake,
                    @"channel_id" : DCServerCommunicator.sharedInstance.selectedChannel.snowflake,
                    @"fail_if_not_exists" : @YES
                }
            }];
            if (disablePing) {
                [dictionary addEntriesFromDictionary:@{
                    @"allowed_mentions" : @{
                        @"parse" : @[ @"users", @"roles", @"everyone" ],
                        @"replied_user" : @NO
                    }
                }];
            }
        } else {
            [dictionary addEntriesFromDictionary:@{
                @"type" : @(DCMessageTypeDefault)
            }];
        }
        NSError *writeError = nil;
        NSData *jsonData    = [NSJSONSerialization dataWithJSONObject:dictionary options:NSJSONWritingPrettyPrinted error:&writeError];
        if (writeError) {
            DBGLOG(@"Error serializing message to JSON: %@", writeError);
            return;
        }
        NSString *messageString = [[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] stringByReplacingOccurrencesOfString:@"\\\\u" withString:@"\\u"];
        DBGLOG(@"[DCChannel] Sending message: %@", messageString);

        [urlRequest setHTTPMethod:@"POST"];

        [urlRequest setHTTPBody:[NSData dataWithBytes:[messageString UTF8String]
                                               length:[messageString length]]];
        [urlRequest addValue:DCServerCommunicator.sharedInstance.token
            forHTTPHeaderField:@"Authorization"];
        [urlRequest addValue:@"application/json"
            forHTTPHeaderField:@"Content-Type"];

        NSError *error                  = nil;
        NSHTTPURLResponse *responseCode = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
        });
        [DCTools checkData:[NSURLConnection sendSynchronousRequest:urlRequest
                                                 returningResponse:&responseCode
                                                             error:&error]
                 withError:error];
        if (responseCode.statusCode != 200) {
            DBGLOG(@"Status code: %ld", (long)responseCode.statusCode);
        }
        dispatch_sync(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        });
    });
}

- (void)editMessage:(DCMessage *)message withContent:(NSString *)content {
    dispatch_async([self get_channel_send_queue], ^{
        NSURL *channelURL = [NSURL
            URLWithString:[NSString
                              stringWithFormat:@"https://discordapp.com/api/v9/channels/%@/messages/%@",
                                               self.snowflake, message.snowflake]];

        NSMutableURLRequest *urlRequest = [NSMutableURLRequest
             requestWithURL:channelURL
                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
            timeoutInterval:10];
        [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];

        // NSString *escapedMessage = [content emojizedString];
        NSString *escapedMessage = content;

        NSDictionary *dictionary = @{@"content" : escapedMessage};
        NSError *writeError      = nil;
        NSData *jsonData         = [NSJSONSerialization dataWithJSONObject:dictionary
                                                           options:NSJSONWritingPrettyPrinted
                                                             error:&writeError];
        if (writeError) {
            DBGLOG(@"Error serializing message to JSON: %@", writeError);
            return;
        }
        NSString *messageString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

        [urlRequest setHTTPMethod:@"PATCH"];

        [urlRequest setHTTPBody:[NSData dataWithBytes:[messageString UTF8String]
                                               length:[messageString length]]];
        [urlRequest addValue:DCServerCommunicator.sharedInstance.token
            forHTTPHeaderField:@"Authorization"];
        [urlRequest addValue:@"application/json"
            forHTTPHeaderField:@"Content-Type"];

        NSError *error                  = nil;
        NSHTTPURLResponse *responseCode = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
        });
        [DCTools checkData:[NSURLConnection sendSynchronousRequest:urlRequest
                                                 returningResponse:&responseCode
                                                             error:&error]
                 withError:error];
        dispatch_sync(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        });
    });
}

- (void)sendImage:(UIImage *)image mimeType:(NSString *)type {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    });
    NSURL *channelURL = [NSURL
        URLWithString:[NSString
                          stringWithFormat:@"https://discordapp.com/api/v9/channels/%@/messages",
                                           self.snowflake]];

    NSMutableURLRequest *urlRequest = [NSMutableURLRequest
         requestWithURL:channelURL
            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
        timeoutInterval:30];
    [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];

    [urlRequest setHTTPMethod:@"POST"];

    NSString *boundary =
        @"---------------------------14737809831466499882746641449";

    NSString *contentType = [NSString
        stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [urlRequest addValue:contentType forHTTPHeaderField:@"Content-Type"];
    [urlRequest addValue:DCServerCommunicator.sharedInstance.token
        forHTTPHeaderField:@"Authorization"];

    NSMutableData *postbody = NSMutableData.new;
    [postbody appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n", boundary]
                             dataUsingEncoding:NSUTF8StringEncoding]];
    NSString *extension = [type substringFromIndex:6];
    [postbody
        appendData:[[NSString stringWithFormat:
                                  @"Content-Disposition: form-data; name=\"file\"; filename=\"upload.%@\"\r\n",
                                  extension]
                       dataUsingEncoding:NSUTF8StringEncoding]];
    if ([type isEqualToString:@"image/jpeg"]) {
        [postbody appendData:[@"Content-Type: image/jpeg\r\n\r\n"
                                 dataUsingEncoding:NSUTF8StringEncoding]];
        [postbody
            appendData:[NSData
                           dataWithData:UIImageJPEGRepresentation(image, 80)]];
    } else if ([type isEqualToString:@"image/png"]) {
        [postbody appendData:[@"Content-Type: image/png\r\n\r\n"
                                 dataUsingEncoding:NSUTF8StringEncoding]];
        [postbody
            appendData:[NSData dataWithData:UIImagePNGRepresentation(image)]];
    }
    [postbody appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n", boundary]
                             dataUsingEncoding:NSUTF8StringEncoding]];
    [postbody
        appendData:[@"Content-Disposition: form-data; name=\"content\"\r\n\r\n "
                       dataUsingEncoding:NSUTF8StringEncoding]];
    [postbody appendData:[[NSString stringWithFormat:@"\r\n--%@--", boundary]
                             dataUsingEncoding:NSUTF8StringEncoding]];

    [urlRequest setHTTPBody:postbody];

    dispatch_async([self get_channel_send_queue], ^{
        NSError *error                  = nil;
        NSHTTPURLResponse *responseCode = nil;

        [DCTools checkData:[NSURLConnection sendSynchronousRequest:urlRequest
                                                 returningResponse:&responseCode
                                                             error:&error]
                 withError:error];
        dispatch_sync(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].networkActivityIndicatorVisible =
                NO;
        });
    });
}

- (void)sendData:(NSData *)data mimeType:(NSString *)type {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    });
    NSURL *channelURL = [NSURL
        URLWithString:[NSString
                          stringWithFormat:@"https://discordapp.com/api/v9/channels/%@/messages",
                                           self.snowflake]];

    NSMutableURLRequest *urlRequest = [NSMutableURLRequest
         requestWithURL:channelURL
            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
        timeoutInterval:30];
    [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];

    [urlRequest setHTTPMethod:@"POST"];

    NSString *boundary =
        @"---------------------------14737809831466499882746641449";

    NSString *contentType = [NSString
        stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [urlRequest addValue:contentType forHTTPHeaderField:@"Content-Type"];
    [urlRequest addValue:DCServerCommunicator.sharedInstance.token
        forHTTPHeaderField:@"Authorization"];

    NSMutableData *postbody = NSMutableData.new;
    [postbody appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n", boundary]
                             dataUsingEncoding:NSUTF8StringEncoding]];
    NSString *extension = [type componentsSeparatedByString:@"/"][1];
    [postbody
        appendData:[[NSString stringWithFormat:
                                  @"Content-Disposition: form-data; "
                                  @"name=\"file\"; filename=\"upload.%@\"\r\n",
                                  extension]
                       dataUsingEncoding:NSUTF8StringEncoding]];

    [postbody appendData:[[NSString
                             stringWithFormat:@"Content-Type: %@\r\n\r\n", type]
                             dataUsingEncoding:NSUTF8StringEncoding]];
    [postbody appendData:data];

    [postbody appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n", boundary]
                             dataUsingEncoding:NSUTF8StringEncoding]];
    [postbody
        appendData:[@"Content-Disposition: form-data; name=\"content\"\r\n\r\n "
                       dataUsingEncoding:NSUTF8StringEncoding]];
    [postbody appendData:[[NSString stringWithFormat:@"\r\n--%@--", boundary]
                             dataUsingEncoding:NSUTF8StringEncoding]];

    [urlRequest setHTTPBody:postbody];

    dispatch_async([self get_channel_send_queue], ^{
        NSError *error                  = nil;
        NSHTTPURLResponse *responseCode = nil;

        [DCTools checkData:[NSURLConnection sendSynchronousRequest:urlRequest
                                                 returningResponse:&responseCode
                                                             error:&error]
                 withError:error];
        dispatch_sync(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].networkActivityIndicatorVisible =
                NO;
        });
    });
}

- (void)sendVideo:(NSURL *)videoURL mimeType:(NSString *)type {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    });
    NSURL *channelURL = [NSURL
        URLWithString:[NSString
                          stringWithFormat:@"https://discordapp.com/api/v9/channels/%@/messages",
                                           self.snowflake]];

    NSMutableURLRequest *urlRequest = [NSMutableURLRequest
         requestWithURL:channelURL
            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
        timeoutInterval:30];

    [urlRequest setHTTPMethod:@"POST"];

    NSString *boundary =
        @"---------------------------14737809831466499882746641449";
    NSString *contentType = [NSString
        stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [urlRequest addValue:contentType forHTTPHeaderField:@"Content-Type"];
    [urlRequest addValue:DCServerCommunicator.sharedInstance.token
        forHTTPHeaderField:@"Authorization"];

    NSMutableData *postbody = NSMutableData.new;

    NSData *videoData = [NSData dataWithContentsOfURL:videoURL];
    NSString *filename =
        [type isEqualToString:@"mov"] ? @"upload.mov" : @"upload.mp4";
    NSString *videoContentType =
        [type isEqualToString:@"mov"] ? @"video/quicktime" : @"video/mp4";

    [postbody appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n", boundary]
                             dataUsingEncoding:NSUTF8StringEncoding]];
    [postbody
        appendData:[[NSString
                       stringWithFormat:@"Content-Disposition: form-data; "
                                        @"name=\"file\"; filename=\"%@\"\r\n",
                                        filename]
                       dataUsingEncoding:NSUTF8StringEncoding]];
    [postbody
        appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n\r\n",
                                               videoContentType]
                       dataUsingEncoding:NSUTF8StringEncoding]];
    [postbody appendData:videoData];
    [postbody appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n", boundary]
                             dataUsingEncoding:NSUTF8StringEncoding]];
    [postbody
        appendData:[@"Content-Disposition: form-data; name=\"content\"\r\n\r\n "
                       dataUsingEncoding:NSUTF8StringEncoding]];
    [postbody appendData:[[NSString stringWithFormat:@"\r\n--%@--", boundary]
                             dataUsingEncoding:NSUTF8StringEncoding]];

    [urlRequest setHTTPBody:postbody];

    dispatch_async([self get_channel_send_queue], ^{
        NSError *error                  = nil;
        NSHTTPURLResponse *responseCode = nil;

        NSData __unused *responseData =
            [NSURLConnection sendSynchronousRequest:urlRequest
                                  returningResponse:&responseCode
                                              error:&error];

        if (error) {
            DBGLOG(@"Error sending video: %@", error.localizedDescription);
        } else {
            DBGLOG(
                @"Response: %@",
                [[NSString alloc] initWithData:responseData
                                      encoding:NSUTF8StringEncoding]
            );
        }

        dispatch_sync(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].networkActivityIndicatorVisible =
                NO;
        });
    });
}

- (void)sendTypingIndicator {
    dispatch_async([self get_channel_event_queue], ^{
        NSURL *channelURL = [NSURL
            URLWithString:[NSString
                              stringWithFormat:@"https://discordapp.com/api/v9/channels/%@/typing",
                                               self.snowflake]];

        NSMutableURLRequest *urlRequest = [NSMutableURLRequest
             requestWithURL:channelURL
                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
            timeoutInterval:5]; // low timeout to avoid API spam
        [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];

        [urlRequest setHTTPMethod:@"POST"];

        [urlRequest addValue:DCServerCommunicator.sharedInstance.token
            forHTTPHeaderField:@"Authorization"];
        [urlRequest addValue:@"application/json"
            forHTTPHeaderField:@"Content-Type"];
        NSError *error                  = nil;
        NSHTTPURLResponse *responseCode = nil;

        //[UIApplication sharedApplication].networkActivityIndicatorVisible =
        // YES; [DCTools checkData:[NSURLConnection
        // sendSynchronousRequest:urlRequest
        // returningResponse:&responseCode error:&error] withError:error];
        [NSURLConnection sendSynchronousRequest:urlRequest
                              returningResponse:&responseCode
                                          error:&error];
        /*[UIApplication sharedApplication].networkActivityIndicatorVisible =
         * NO;*/
    });
}

- (void)ackMessage:(NSString *)messageId {
    self.lastReadMessageId = messageId;
    dispatch_async([self get_channel_event_queue], ^{
        NSURL *channelURL = [NSURL
            URLWithString:[NSString
                              stringWithFormat:@"https://discordapp.com/api/v9/channels/%@/messages/%@/ack",
                                               self.snowflake, messageId]];

        NSMutableURLRequest *urlRequest = [NSMutableURLRequest
             requestWithURL:channelURL
                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
            timeoutInterval:10];
        [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];

        [urlRequest setHTTPMethod:@"POST"];

        [urlRequest addValue:DCServerCommunicator.sharedInstance.token
            forHTTPHeaderField:@"Authorization"];
        [urlRequest addValue:@"application/json"
            forHTTPHeaderField:@"Content-Type"];
        NSError *error                  = nil;
        NSHTTPURLResponse *responseCode = nil;

        NSMutableData *postbody = NSMutableData.new;

        [postbody appendData:[@"{\"token\":null,\"last_viewed\":3287}"
                                 dataUsingEncoding:NSUTF8StringEncoding]];

        [urlRequest setHTTPBody:postbody];

        //[UIApplication sharedApplication].networkActivityIndicatorVisible =
        // YES; [DCTools checkData:[NSURLConnection
        // sendSynchronousRequest:urlRequest
        // returningResponse:&responseCode error:&error] withError:error];
        [NSURLConnection sendSynchronousRequest:urlRequest
                              returningResponse:&responseCode
                                          error:&error];
        /*[UIApplication sharedApplication].networkActivityIndicatorVisible =
         * NO;*/
    });
}

- (NSArray *)getMessages:(int)numberOfMessages
           beforeMessage:(DCMessage *)message {
    NSMutableArray *messages = NSMutableArray.new;
    NSData *response         = nil;
    // Generate URL from args
    NSMutableString *getChannelAddress = [NSMutableString
        stringWithFormat:@"https://discordapp.com/api/v9/channels/%@/messages?",
                         self.snowflake];

    if (numberOfMessages) {
        [getChannelAddress
            appendString:[NSString
                             stringWithFormat:@"limit=%d", numberOfMessages]];
    }
    if (numberOfMessages && message) {
        [getChannelAddress appendString:@"&"];
    }
    if (message) {
        [getChannelAddress
            appendString:[NSString
                             stringWithFormat:@"before=%@", message.snowflake]];
    }

    NSMutableURLRequest *urlRequest = [NSMutableURLRequest
         requestWithURL:[NSURL URLWithString:getChannelAddress]
            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
        timeoutInterval:15];
    [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];

    [urlRequest addValue:DCServerCommunicator.sharedInstance.token
        forHTTPHeaderField:@"Authorization"];
    [urlRequest addValue:@"application/json"
        forHTTPHeaderField:@"Content-Type"];

    NSError *error                  = nil;
    NSHTTPURLResponse *responseCode = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    });
    NSData *uncheckedResponse =
        [NSURLConnection sendSynchronousRequest:urlRequest
                              returningResponse:&responseCode
                                          error:&error];
    response = [DCTools checkData:uncheckedResponse withError:error];
    dispatch_sync(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    });
    if (!response || responseCode == nil || responseCode.statusCode != 200) {
        return nil;
    }

    // starting here it gets important
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSError *error = nil;
        NSArray *parsedResponse =
            [NSJSONSerialization JSONObjectWithData:response
                                            options:0
                                              error:&error];

        if (error) {
            NSLog(@"Error: %@", error);
            return;
        }

        /*if(parsedResponse.count > 0)
            for(NSDictionary* jsonMessage in parsedResponse)
                [messages insertObject:[DCTools convertJsonMessage:jsonMessage]
           atIndex:0];*/
        if (parsedResponse.count <= 0) {
            return;
        }

        static NSArray *joinMessages;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            joinMessages = @[
                @"%@ joined the party.",
                @"%@ is here.",
                @"Welcome, %@. We hope you brought pizza.",
                @"A wild %@ appeared.",
                @"%@ just landed.",
                @"%@ just slid into the server.",
                @"%@ just showed up!",
                @"Welcome %@. Say hi!",
                @"%@ hopped into the server.",
                @"Everyone welcome %@!",
                @"Glad you're here, %@.",
                @"Good to see you, %@.",
                @"Yay you made it, %@!",
            ];
        });

        for (NSDictionary *jsonMessage in parsedResponse) {
            @autoreleasepool {
                DCMessage *convertedMessage =
                    [DCTools convertJsonMessage:jsonMessage];

                NSString *messageType = [jsonMessage objectForKey:@"type"];

                if ([messageType intValue] == DCMessageTypeRecipientAdd) {
                    NSArray *mentions     = [jsonMessage objectForKey:@"mentions"];
                    NSDictionary *mention = mentions.firstObject;
                    // NSString *targetName = [mentions
                    // objectForKey:@"global_name"];
                    convertedMessage.isGrouped = NO;
                    NSString *targetUsername =
                        [mention objectForKey:@"global_name"];
                    if ([targetUsername isKindOfClass:[NSNull class]]) {
                        targetUsername = @"Deleted User";
                    }
                    convertedMessage.content       = [NSString
                        stringWithFormat:@"%@ added %@ to the group conversation.",
                                         convertedMessage.author.globalName,
                                         targetUsername];
                    float contentWidth             = UIScreen.mainScreen.bounds.size.width - 63;
                    CGSize textSize                = [convertedMessage.content
                             sizeWithFont:[UIFont systemFontOfSize:15]
                        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                            lineBreakMode:NSLineBreakByWordWrapping];
                    convertedMessage.contentHeight = textSize.height + 40;
                } else if ([messageType intValue] == DCMessageTypeRecipientRemove) {
                    convertedMessage.isGrouped     = NO;
                    convertedMessage.content       = [NSString
                        stringWithFormat:@"%@ left the group conversation.",
                                         convertedMessage.author.globalName];
                    float contentWidth             = UIScreen.mainScreen.bounds.size.width - 63;
                    CGSize textSize                = [convertedMessage.content
                             sizeWithFont:[UIFont systemFontOfSize:15]
                        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                            lineBreakMode:NSLineBreakByWordWrapping];
                    convertedMessage.contentHeight = textSize.height + 40;
                } else if ([messageType intValue] == DCMessageTypeChannelNameChange) {
                    convertedMessage.isGrouped     = NO;
                    convertedMessage.content       = [NSString
                        stringWithFormat:@"%@ changed the group name to %@.",
                                         convertedMessage.author.globalName,
                                         [jsonMessage objectForKey:@"content"]];
                    float contentWidth             = UIScreen.mainScreen.bounds.size.width - 63;
                    CGSize textSize                = [convertedMessage.content
                             sizeWithFont:[UIFont systemFontOfSize:15]
                        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                            lineBreakMode:NSLineBreakByWordWrapping];
                    convertedMessage.contentHeight = textSize.height + 30;
                } else if ([messageType intValue] == DCMessageTypeChannelIconChange) {
                    convertedMessage.isGrouped     = NO;
                    convertedMessage.content       = [NSString
                        stringWithFormat:@"%@ changed the group icon.",
                                         convertedMessage.author.globalName];
                    float contentWidth             = UIScreen.mainScreen.bounds.size.width - 63;
                    CGSize textSize                = [convertedMessage.content
                             sizeWithFont:[UIFont systemFontOfSize:15]
                        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                            lineBreakMode:NSLineBreakByWordWrapping];
                    convertedMessage.contentHeight = textSize.height + 15;
                } else if ([messageType intValue] == DCMessageTypeChannelPinnedMessage) {
                    convertedMessage.isGrouped     = NO;
                    convertedMessage.content       = [NSString
                        stringWithFormat:@"%@ pinned a message to this channel.",
                                         convertedMessage.author.globalName];
                    float contentWidth             = UIScreen.mainScreen.bounds.size.width - 63;
                    CGSize textSize                = [convertedMessage.content
                             sizeWithFont:[UIFont systemFontOfSize:15]
                        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                            lineBreakMode:NSLineBreakByWordWrapping];
                    convertedMessage.contentHeight = textSize.height + 40;
                } else if ([messageType intValue] == DCMessageTypeUserJoin) {
                    convertedMessage.isGrouped     = NO;
                    static dispatch_once_t dateFormatOnceToken;
                    static NSDateFormatter *dateFormatter;
                    dispatch_once(&dateFormatOnceToken, ^{
                        dateFormatter = [NSDateFormatter new];
                        dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSSSS+00':'00";
                        dateFormatter.timeZone     = [NSTimeZone timeZoneWithName:@"GMT"];
                        dateFormatter.locale     = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
                    });
                    NSDate *timestamp = [dateFormatter dateFromString:[jsonMessage objectForKey:@"timestamp"]];
                    uint64_t time = [timestamp timeIntervalSince1970] * 1000; // ms
                    convertedMessage.content       = [NSString
                        stringWithFormat:joinMessages[time % joinMessages.count],
                                         convertedMessage.author.globalName];
                    float contentWidth             = UIScreen.mainScreen.bounds.size.width - 63;
                    CGSize textSize                = [convertedMessage.content
                             sizeWithFont:[UIFont systemFontOfSize:15]
                        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                            lineBreakMode:NSLineBreakByWordWrapping];
                    convertedMessage.contentHeight = textSize.height + 20;
                } else if ([messageType intValue] == DCMessageTypeGuildBoost) {
                    convertedMessage.isGrouped     = NO;
                    convertedMessage.content       = [NSString
                        stringWithFormat:@"%@ just boosted the server!",
                                         convertedMessage.author.globalName];
                    float contentWidth             = UIScreen.mainScreen.bounds.size.width - 63;
                    CGSize textSize                = [convertedMessage.content
                             sizeWithFont:[UIFont systemFontOfSize:15]
                        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                            lineBreakMode:NSLineBreakByWordWrapping];
                    convertedMessage.contentHeight = textSize.height + 20;
                } else if ([messageType intValue] == DCMessageTypeThreadCreated) {
                    convertedMessage.isGrouped     = NO;
                    convertedMessage.content       = [NSString
                        stringWithFormat:@"%@ just boosted the server!",
                                         convertedMessage.author.globalName];
                    float contentWidth             = UIScreen.mainScreen.bounds.size.width - 63;
                    CGSize textSize                = [convertedMessage.content
                             sizeWithFont:[UIFont systemFontOfSize:15]
                        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                            lineBreakMode:NSLineBreakByWordWrapping];
                    convertedMessage.contentHeight = textSize.height + 20;
                }

                [messages insertObject:convertedMessage atIndex:0];
            }
        }

        for (int i = 0; i < messages.count; i++) {
            DCMessage *prevMessage =
                i == 0 ? message : [messages objectAtIndex:i - 1];
            DCMessage *currentMessage = [messages objectAtIndex:i];
            if (prevMessage == nil) {
                continue;
            }
            NSDate *currentTimeStamp = currentMessage.timestamp;

            if (prevMessage.author.snowflake != currentMessage.author.snowflake
                || ([currentMessage.timestamp timeIntervalSince1970] -
                        [prevMessage.timestamp timeIntervalSince1970]
                    >= 420)
                || ![[NSCalendar currentCalendar]
                    rangeOfUnit:NSCalendarUnitDay
                      startDate:&currentTimeStamp
                       interval:NULL
                        forDate:prevMessage.timestamp]
                || (prevMessage.messageType != DCMessageTypeDefault && prevMessage.messageType != DCMessageTypeReply)) {
                continue;
            }

            currentMessage.isGrouped = (currentMessage.messageType == DCMessageTypeDefault || currentMessage.messageType == DCMessageTypeReply)
                && (currentMessage.referencedMessage == nil);
            if (!currentMessage.isGrouped) {
                continue;
            }

            float contentWidth =
                UIScreen.mainScreen.bounds.size.width - 63;
            CGSize authorNameSize = [currentMessage.author.globalName
                     sizeWithFont:[UIFont boldSystemFontOfSize:15]
                constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                    lineBreakMode:(NSLineBreakMode)UILineBreakModeWordWrap];

            currentMessage.contentHeight -= authorNameSize.height + 4;
        }
    });

    if (messages.count > 0) {
        return messages;
    }

    [DCTools alert:@"No messages!"
        withMessage:@"No further messages could be found"];

    return nil;
}

// a

#if 0
- (NSArray*)getMessages:(int)numberOfMessages
 beforeMessage:(DCMessage*)message {

 NSMutableArray* messages = NSMutableArray.new;
 // Generate URL from args
 NSMutableString* getChannelAddress = [[NSString stringWithFormat:
 @"https://discordapp.com/api/v9/channels/%@/messages?", self.snowflake]
 mutableCopy];

 if (numberOfMessages)
 [getChannelAddress appendString:[NSString stringWithFormat:@"limit=%i",
 numberOfMessages]]; if (numberOfMessages && message) [getChannelAddress
 appendString:@"&"]; if (message) [getChannelAddress appendString:[NSString
 stringWithFormat:@"before=%@", message.snowflake]];

 NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:[NSURL
 URLWithString:getChannelAddress]
 cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
 [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];

 [urlRequest addValue:DCServerCommunicator.sharedInstance.token
 forHTTPHeaderField:@"Authorization"]; [urlRequest addValue:@"application/json"
 forHTTPHeaderField:@"Content-Type"];

 NSError *error = nil;
 NSHTTPURLResponse *responseCode = nil;
 dispatch_sync(dispatch_get_main_queue(), ^{
 [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
 });

 NSData *response = [DCTools checkData:[NSURLConnection
 sendSynchronousRequest:urlRequest returningResponse:&responseCode error:&error]
 withError:error];

 dispatch_sync(dispatch_get_main_queue(), ^{
 if ([UIApplication sharedApplication].networkActivityIndicatorVisible > 0)
 [UIApplication sharedApplication].networkActivityIndicatorVisible--;
 else if ([UIApplication sharedApplication].networkActivityIndicatorVisible < 0)
 [UIApplication sharedApplication].networkActivityIndicatorVisible = 0;
 });

 if (response) {
 dispatch_sync(dispatch_get_main_queue(), ^{
 NSError *error = nil;
 NSArray* parsedResponse = [NSJSONSerialization JSONObjectWithData:response
 options:0 error:&error];

 NSLog(@"[getMessages] Original JSON payload: %@", parsedResponse);

 if (parsedResponse.count > 0) {
 for (NSDictionary* jsonMessage in parsedResponse) {
 // Check if the message is a call
 NSDictionary *callData = [jsonMessage objectForKey:@"call"];

 if (callData != nil) {
 // Handle call messages
 NSString *endedTimestamp = [callData objectForKey:@"ended_timestamp"];
 NSArray *participants = [callData objectForKey:@"participants"];
 NSMutableDictionary *mutableJsonMessage = [jsonMessage mutableCopy];

 // Setup the date formatter for both timestamps
 NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
 [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss"];  // Adjusted format for
 seconds [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
 // Set UTC for consistency

 // Function to truncate timestamp strings
 NSString* (^truncateTimestamp)(NSString*) = ^NSString* (NSString* timestamp) {
 if (timestamp.length > 19) {
 return [timestamp substringToIndex:19];  // Truncate after seconds
 }
 return timestamp;
 };

 // Truncate the timestamps before parsing
 NSString *startTimestamp = truncateTimestamp([jsonMessage
 objectForKey:@"timestamp"]); NSString *truncatedEndTimestamp =
 truncateTimestamp(endedTimestamp);

 NSDate *startDate = [formatter dateFromString:startTimestamp];
 NSDate *endDate = [formatter dateFromString:truncatedEndTimestamp];

 NSLog(@"[getMessages] Parsed startDate: %@ from timestamp: %@", startDate,
 startTimestamp); NSLog(@"[getMessages] Parsed endDate: %@ from ended_timestamp:
 %@", endDate, truncatedEndTimestamp);

 // Differentiate between missed, ongoing, and normal calls
 NSString *callStatus = @"";
 if (participants.count == 1) {
 currentMessage.missedCall = YES;
 // Missed call handling
 if (startDate) {
 NSDate *currentDate = [NSDate date];
 NSTimeInterval timeDifference = [currentDate timeIntervalSinceDate:startDate];
 NSInteger hours = timeDifference / 3600;
 NSInteger minutes = (timeDifference / 60) / 60;

 NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
 [dateFormatter setDateFormat:@"d MMMM yyyy 'at' HH:mm"];  // For long format
 display

 if (timeDifference < 24 * 3600) {
 if (hours > 0) {
 callStatus = [NSString stringWithFormat:@"📞 Missed call %ld hours ago",
 (long)hours]; } else { callStatus = [NSString stringWithFormat:@"📞 Missed call
 %ld minutes ago", (long)minutes];
 }
 } else {
 // Display full date and time if older than 24 hours
 callStatus = [NSString stringWithFormat:@"📞 Missed call on %@", [dateFormatter
 stringFromDate:startDate]];
 }
 } else {
 callStatus = @"📞 Missed call";
 }
 } else if (participants.count >= 2 && endedTimestamp != nil) {
 // Normal call if two or more participants and an end timestamp
 if (startDate && endDate) {
 NSTimeInterval duration = [endDate timeIntervalSinceDate:startDate];
 NSInteger hours = duration / 3600;
 NSInteger minutes = (NSInteger)(duration / 60) % 60;

 NSLog(@"[getMessages] Call duration: %ld hours, %ld minutes", (long)hours,
 (long)minutes);

 if (hours > 0) {
 callStatus = [NSString stringWithFormat:@"📞 Call that lasted %ld hours and %ld
 minutes", (long)hours, (long)minutes]; } else if (minutes > 0) { callStatus =
 [NSString stringWithFormat:@"📞 Call that lasted %ld minutes", (long)minutes];
 } else {
 callStatus = @"📞 Call that lasted less than a minute";
 }
 } else {
 callStatus = @"📞 Call with unknown duration";
 }
 } else if (participants.count >= 2 && endedTimestamp == nil) {
 // Ongoing call if two or more participants and no end timestamp
 callStatus = @"📞 Ongoing call";
 }

 // Set the calculated call status as content
 [mutableJsonMessage setObject:callStatus forKey:@"content"];

 [messages insertObject:[DCTools convertJsonMessage:mutableJsonMessage]
 atIndex:0]; } else {
 // Handle normal messages like replies, images, etc.
 BOOL hasAttachments = [jsonMessage objectForKey:@"attachments"] != nil;
 BOOL isReply = [jsonMessage objectForKey:@"referenced_message"] != nil;
 NSNumber *messageType = [jsonMessage objectForKey:@"type"];

 if (isReply) {
 // Process replies normally
 [messages insertObject:[DCTools convertJsonMessage:jsonMessage] atIndex:0];
 } else if (hasAttachments) {
 // Process attachments (images, etc.)
 [messages insertObject:[DCTools convertJsonMessage:jsonMessage] atIndex:0];
 } else if (messageType != nil && [messageType integerValue] != 0) {
 // Replace unsupported message types
 NSMutableDictionary *mutableJsonMessage = [jsonMessage mutableCopy];
 [mutableJsonMessage setObject:@"Unsupported message type" forKey:@"content"];
 [messages insertObject:[DCTools convertJsonMessage:mutableJsonMessage]
 atIndex:0]; } else {
 // Normal text message
 [messages insertObject:[DCTools convertJsonMessage:jsonMessage] atIndex:0];
 }
 }
 }
 }

 for (int i = 0; i < messages.count; i++) {
 DCMessage* prevMessage;
 if (i == 0)
 prevMessage = message;
 else
 prevMessage = [messages objectAtIndex:i-1];

 DCMessage* currentMessage = [messages objectAtIndex:i];

 if (prevMessage != nil) {
 NSDateComponents* curComponents = [[NSCalendar currentCalendar]
 components:kCFCalendarUnitHour | kCFCalendarUnitDay | kCFCalendarUnitMonth |
 kCFCalendarUnitYear fromDate:currentMessage.timestamp]; NSDateComponents*
 prevComponents = [[NSCalendar currentCalendar] components:kCFCalendarUnitHour |
 kCFCalendarUnitDay | kCFCalendarUnitMonth | kCFCalendarUnitYear
 fromDate:prevMessage.timestamp];

 if (prevMessage.author.snowflake == currentMessage.author.snowflake
 && ([currentMessage.timestamp timeIntervalSince1970] - [prevMessage.timestamp
 timeIntervalSince1970] < 420)
 && curComponents.day == prevComponents.day
 && curComponents.month == prevComponents.month
 && curComponents.year == prevComponents.year) {
 currentMessage.isGrouped = currentMessage.referencedMessage == nil;

 if (currentMessage.isGrouped) {
 float contentWidth = UIScreen.mainScreen.bounds.size.width - 63;
 CGSize authorNameSize = [currentMessage.author.globalName sizeWithFont:[UIFont
 boldSystemFontOfSize:15] constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
 lineBreakMode:UILineBreakModeWordWrap];

 currentMessage.contentHeight -= authorNameSize.height + 4;
 }
 }
 }
 }
 });

 if (messages.count > 0)
 return messages;

 [DCTools alert:@"No messages!" withMessage:@"No further messages could be
 found"];
 }

 return nil;
 }
#endif

@end
