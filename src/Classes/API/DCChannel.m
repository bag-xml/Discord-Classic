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
    self.unread = (self.mentionCount > 0) || 
                  (self.lastMessageId && 
                   self.lastMessageId != (id)NSNull.null && 
                   [self.lastMessageId isKindOfClass:[NSString class]] && 
                   ![self.lastMessageId isEqualToString:self.lastReadMessageId]);
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
        NSMutableURLRequest *urlRequest = [DCServerCommunicator
            requestWithPath:[NSString stringWithFormat:@"/channels/%@/messages", self.snowflake]
                      token:DCServerCommunicator.sharedInstance.token];
        [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];

        // NSString *escapedMessage = [message emojizedString];
        NSString *escapedMessage = message;
        CFStringRef transform = CFSTR("Any-Hex/Java");
        NSMutableString *mutableMessage = [escapedMessage mutableCopy];
        CFStringTransform((__bridge CFMutableStringRef)mutableMessage, NULL, transform, NO);
        NSMutableDictionary *dictionary = [@{
            @"content" : mutableMessage
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

        NSError *error                  = nil;
        NSHTTPURLResponse *responseCode = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
        });
        NSData *responseData = nil;
        NSInteger maxRetries = 3;
        NSInteger attempt = 0;

        while (attempt < maxRetries) {
            responseData = [DCTools checkData:[NSURLConnection sendSynchronousRequest:urlRequest
                                                                   returningResponse:&responseCode
                                                                               error:&error]
                                    withError:error];
            if (responseData && responseCode.statusCode == 200) {
                break;
            }
            attempt++;
            if (attempt < maxRetries) {
                [NSThread sleepForTimeInterval:1.0];
            }
        }

        if (!responseData || responseCode.statusCode != 200) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertView *alert = [[UIAlertView alloc]
                    initWithTitle:@"Failed to Send"
                          message:@"Your message could not be sent. Please check your connection and try again."
                         delegate:nil
                cancelButtonTitle:@"OK"
                otherButtonTitles:nil];
                [alert show];
            });
        }
        dispatch_sync(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        });
    });
}

- (void)editMessage:(DCMessage *)message withContent:(NSString *)content {
    dispatch_async([self get_channel_send_queue], ^{

        NSMutableURLRequest *urlRequest = [DCServerCommunicator 
            requestWithPath:[NSString stringWithFormat:@"/channels/%@/messages/%@", 
                self.snowflake, message.snowflake]
                      token:DCServerCommunicator.sharedInstance.token];
        [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];
        [urlRequest setHTTPMethod:@"PATCH"];

        NSMutableString *mutableContent = [content mutableCopy];

        NSDictionary *dictionary = @{@"content" : mutableContent};
        NSError *writeError = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dictionary
                                                           options:NSJSONWritingPrettyPrinted
                                                             error:&writeError];
        if (writeError) {
            DBGLOG(@"Error serializing message to JSON: %@", writeError);
            return;
        }
        NSString *messageString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        [urlRequest setHTTPBody:[NSData dataWithBytes:[messageString UTF8String]
                                               length:[messageString length]]];

        NSError *error                  = nil;
        NSHTTPURLResponse *responseCode = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
        });
        NSData *responseData = nil;
        NSInteger maxRetries = 3;
        NSInteger attempt = 0;

        while (attempt < maxRetries) {
            responseData = [DCTools checkData:[NSURLConnection sendSynchronousRequest:urlRequest
                                                                   returningResponse:&responseCode
                                                                               error:&error]
                                    withError:error];
            if (responseData && responseCode.statusCode == 200) {
                break;
            }
            attempt++;
            if (attempt < maxRetries) {
                [NSThread sleepForTimeInterval:1.0];
            }
        }

        if (!responseData || responseCode.statusCode != 200) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertView *alert = [[UIAlertView alloc]
                    initWithTitle:@"Failed to Edit"
                          message:@"Your message could not be edited. Please check your connection and try again."
                         delegate:nil
                cancelButtonTitle:@"OK"
                otherButtonTitles:nil];
                [alert show];
            });
        }
        dispatch_sync(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        });
    });
}

- (void)deleteMessage:(DCMessage *)message {
    dispatch_async([self get_channel_send_queue], ^{
        NSMutableURLRequest *urlRequest = [DCServerCommunicator
            requestWithPath:[NSString stringWithFormat:@"/channels/%@/messages/%@",
                self.snowflake, message.snowflake]
                      token:DCServerCommunicator.sharedInstance.token];
        [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];
        [urlRequest setHTTPMethod:@"DELETE"];

        dispatch_sync(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
        });
        __block NSInteger attempt = 0;
        NSInteger maxRetries = 3;

        __block void (^retryBlock)(void) = ^{
            [NSURLConnection
                sendAsynchronousRequest:urlRequest
                                  queue:[NSOperationQueue currentQueue]
                      completionHandler:^(NSURLResponse *response, NSData *data, NSError *connError) {
                          NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                          if ((!connError && httpResponse.statusCode == 204) || attempt >= maxRetries) {
                              dispatch_async(dispatch_get_main_queue(), ^{
                                  [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
                                  if (connError || httpResponse.statusCode != 204) {
                                      UIAlertView *alert = [[UIAlertView alloc]
                                          initWithTitle:@"Failed to Delete"
                                                message:@"Your message could not be deleted. Please check your connection and try again."
                                               delegate:nil
                                      cancelButtonTitle:@"OK"
                                      otherButtonTitles:nil];
                                      [alert show];
                                  }
                              });
                          } else {
                              attempt++;
                              [NSThread sleepForTimeInterval:1.0];
                              retryBlock();
                          }
                      }];
        };
        retryBlock();
    });
}

- (void)sendImage:(UIImage *)image mimeType:(NSString *)type {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    });
    NSMutableURLRequest *urlRequest = [DCServerCommunicator
        requestWithPath:[NSString stringWithFormat:@"/channels/%@/messages", self.snowflake]
                  token:DCServerCommunicator.sharedInstance.token];
    [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];
    [urlRequest setHTTPMethod:@"POST"];
    NSString *boundary = @"---------------------------14737809831466499882746641449";
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [urlRequest setValue:contentType forHTTPHeaderField:@"Content-Type"];

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
    NSMutableURLRequest *urlRequest = [DCServerCommunicator
            requestWithPath:[NSString stringWithFormat:@"/channels/%@/messages", self.snowflake]
                      token:DCServerCommunicator.sharedInstance.token];
    [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];
    [urlRequest setHTTPMethod:@"POST"];
    NSString *boundary = @"---------------------------14737809831466499882746641449";
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [urlRequest setValue:contentType forHTTPHeaderField:@"Content-Type"];

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
    NSMutableURLRequest *urlRequest = [DCServerCommunicator
            requestWithPath:[NSString stringWithFormat:@"/channels/%@/messages", self.snowflake]
                      token:DCServerCommunicator.sharedInstance.token];
    [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];
    [urlRequest setHTTPMethod:@"POST"];
    NSString *boundary = @"---------------------------14737809831466499882746641449";
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [urlRequest setValue:contentType forHTTPHeaderField:@"Content-Type"];

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
        NSMutableURLRequest *urlRequest = [DCServerCommunicator
            requestWithPath:[NSString stringWithFormat:@"/channels/%@/typing", self.snowflake]
                      token:DCServerCommunicator.sharedInstance.token];
        [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];
        [urlRequest setHTTPMethod:@"POST"];
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
    self.mentionCount = 0;
    dispatch_async([self get_channel_event_queue], ^{
        NSMutableURLRequest *urlRequest = [DCServerCommunicator
            requestWithPath:[NSString stringWithFormat:@"/channels/%@/messages/%@/ack", 
                self.snowflake, messageId]
                      token:DCServerCommunicator.sharedInstance.token];
        [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];
        [urlRequest setHTTPMethod:@"POST"];

        NSMutableData *postbody = NSMutableData.new;
        [postbody appendData:[@"{\"token\":null,\"last_viewed\":3287}"
            dataUsingEncoding:NSUTF8StringEncoding]];
        NSError *error                  = nil;
        NSHTTPURLResponse *responseCode = nil;

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
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:@"MENTION_COUNT_UPDATED" object:nil];
    });
}

- (NSArray *)getMessages:(int)numberOfMessages
           beforeMessage:(DCMessage *)message {
    NSMutableArray *messages = NSMutableArray.new;
    NSData *response         = nil;
    // Generate URL from args
    NSMutableString *path = [NSMutableString
        stringWithFormat:@"/channels/%@/messages?", self.snowflake];

    if (numberOfMessages) {
        [path appendString:[NSString stringWithFormat:@"limit=%d", numberOfMessages]];
    }
    if (numberOfMessages && message) {
        [path appendString:@"&"];
    }
    if (message) {
        [path appendString:[NSString stringWithFormat:@"before=%@", message.snowflake]];
    }

    NSMutableURLRequest *urlRequest = [DCServerCommunicator
        requestWithPath:path
                  token:DCServerCommunicator.sharedInstance.token];
    [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];

    NSError *error                  = nil;
    NSHTTPURLResponse *responseCode = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    });
    NSData *uncheckedResponse = nil;
    NSInteger maxRetries = 3;
    NSInteger attempt = 0;

    while (attempt < maxRetries && !uncheckedResponse) {
        uncheckedResponse = [NSURLConnection sendSynchronousRequest:urlRequest
                                                  returningResponse:&responseCode
                                                              error:&error];
        if (!uncheckedResponse || responseCode.statusCode != 200) {
            attempt++;
            if (attempt < maxRetries) {
                NSLog(@"[DCChannel] Request failed, retrying (%ld/%ld)...", (long)attempt, (long)maxRetries);
                [NSThread sleepForTimeInterval:1.0];
                uncheckedResponse = nil;
            }
        } else {
            break;
        }
    }

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
                                         [convertedMessage.author displayName],
                                         targetUsername];
                    float contentWidth             = UIScreen.mainScreen.bounds.size.width - 63;
                    CGSize textSize                = [convertedMessage.content
                             sizeWithFont:[UIFont systemFontOfSize:14]
                        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                            lineBreakMode:NSLineBreakByWordWrapping];
                    convertedMessage.contentHeight = textSize.height + 40;
                } else if ([messageType intValue] == DCMessageTypeRecipientRemove) {
                    convertedMessage.isGrouped     = NO;
                    convertedMessage.content       = [NSString
                        stringWithFormat:@"%@ left the group conversation.",
                                         [convertedMessage.author displayName]];
                    float contentWidth             = UIScreen.mainScreen.bounds.size.width - 63;
                    CGSize textSize                = [convertedMessage.content
                             sizeWithFont:[UIFont systemFontOfSize:14]
                        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                            lineBreakMode:NSLineBreakByWordWrapping];
                    convertedMessage.contentHeight = textSize.height + 40;
                } else if ([messageType intValue] == DCMessageTypeChannelNameChange) {
                    convertedMessage.isGrouped     = NO;
                    convertedMessage.content       = [NSString
                        stringWithFormat:@"%@ changed the group name to %@.",
                                         [convertedMessage.author displayName],
                                         [jsonMessage objectForKey:@"content"]];
                    float contentWidth             = UIScreen.mainScreen.bounds.size.width - 63;
                    CGSize textSize                = [convertedMessage.content
                             sizeWithFont:[UIFont systemFontOfSize:14]
                        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                            lineBreakMode:NSLineBreakByWordWrapping];
                    convertedMessage.contentHeight = textSize.height + 30;
                } else if ([messageType intValue] == DCMessageTypeChannelIconChange) {
                    convertedMessage.isGrouped     = NO;
                    convertedMessage.content       = [NSString
                        stringWithFormat:@"%@ changed the group icon.",
                                         [convertedMessage.author displayName]];
                    float contentWidth             = UIScreen.mainScreen.bounds.size.width - 63;
                    CGSize textSize                = [convertedMessage.content
                             sizeWithFont:[UIFont systemFontOfSize:14]
                        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                            lineBreakMode:NSLineBreakByWordWrapping];
                    convertedMessage.contentHeight = textSize.height + 15;
                } else if ([messageType intValue] == DCMessageTypeChannelPinnedMessage) {
                    convertedMessage.isGrouped     = NO;
                    convertedMessage.content       = [NSString
                        stringWithFormat:@"%@ pinned a message to this channel.",
                                         [convertedMessage.author displayName]];
                    float contentWidth             = UIScreen.mainScreen.bounds.size.width - 63;
                    CGSize textSize                = [convertedMessage.content
                             sizeWithFont:[UIFont systemFontOfSize:14]
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
                                         [convertedMessage.author displayName]];
                    float contentWidth             = UIScreen.mainScreen.bounds.size.width - 63;
                    CGSize textSize                = [convertedMessage.content
                             sizeWithFont:[UIFont systemFontOfSize:14]
                        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                            lineBreakMode:NSLineBreakByWordWrapping];
                    convertedMessage.contentHeight = textSize.height + 20;
                } else if ([messageType intValue] == DCMessageTypeGuildBoost) {
                    convertedMessage.isGrouped     = NO;
                    convertedMessage.content       = [NSString
                        stringWithFormat:@"%@ just boosted the server!",
                                         [convertedMessage.author displayName]];
                    float contentWidth             = UIScreen.mainScreen.bounds.size.width - 63;
                    CGSize textSize                = [convertedMessage.content
                             sizeWithFont:[UIFont systemFontOfSize:14]
                        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                            lineBreakMode:NSLineBreakByWordWrapping];
                    convertedMessage.contentHeight = textSize.height + 20;
                } else if ([messageType intValue] == DCMessageTypeThreadCreated) {
                    convertedMessage.isGrouped     = NO;
                    convertedMessage.content       = [NSString
                        stringWithFormat:@"%@ started a thread: 'placeholder'. See all 'placeholder'.",
                                         [convertedMessage.author displayName]];
                    float contentWidth             = UIScreen.mainScreen.bounds.size.width - 63;
                    CGSize textSize                = [convertedMessage.content
                             sizeWithFont:[UIFont systemFontOfSize:14]
                        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                            lineBreakMode:NSLineBreakByWordWrapping];
                    convertedMessage.contentHeight = textSize.height + 20;
                }
                // NSLog(@"[DCChannel] snowflake: %@ contentHeight: %f", convertedMessage.snowflake, convertedMessage.contentHeight);
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
            CGSize authorNameSize = [[currentMessage.author displayName]
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

- (NSArray *)getMessages:(int)numberOfMessages
            afterMessage:(DCMessage *)message {
    NSMutableArray *messages = NSMutableArray.new;
    NSData *response         = nil;

    NSMutableString *path = [NSMutableString
        stringWithFormat:@"/channels/%@/messages?", self.snowflake];

    if (numberOfMessages) {
        [path appendString:[NSString stringWithFormat:@"limit=%d", numberOfMessages]];
    }
    if (numberOfMessages && message) {
        [path appendString:@"&"];
    }
    if (message) {
        [path appendString:[NSString stringWithFormat:@"after=%@", message.snowflake]];
    }

    NSMutableURLRequest *urlRequest = [DCServerCommunicator
        requestWithPath:path
                  token:DCServerCommunicator.sharedInstance.token];
    [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];

    NSError *error                  = nil;
    NSHTTPURLResponse *responseCode = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    });

    NSData *uncheckedResponse = nil;
    NSInteger maxRetries      = 3;
    NSInteger attempt         = 0;
    while (attempt < maxRetries && !uncheckedResponse) {
        uncheckedResponse = [NSURLConnection sendSynchronousRequest:urlRequest
                                                  returningResponse:&responseCode
                                                              error:&error];
        if (!uncheckedResponse || responseCode.statusCode != 200) {
            attempt++;
            if (attempt < maxRetries) {
                NSLog(@"[DCChannel] afterMessage request failed, retrying (%ld/%ld)...", (long)attempt, (long)maxRetries);
                [NSThread sleepForTimeInterval:1.0];
                uncheckedResponse = nil;
            }
        } else {
            break;
        }
    }

    response = [DCTools checkData:uncheckedResponse withError:error];
    dispatch_sync(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    });

    if (!response || responseCode == nil || responseCode.statusCode != 200) {
        return nil;
    }

    dispatch_sync(dispatch_get_main_queue(), ^{
        NSError *parseError = nil;
        NSArray *parsedResponse = [NSJSONSerialization JSONObjectWithData:response
                                                                  options:0
                                                                    error:&parseError];
        if (parseError || parsedResponse.count <= 0) {
            return;
        }

        // after= returns messages in ascending order (oldest first),
        // so we append rather than insert at index 0
        for (NSDictionary *jsonMessage in parsedResponse) {
            DCMessage *convertedMessage = [DCTools convertJsonMessage:jsonMessage];
            if (convertedMessage) {
                [messages addObject:convertedMessage];
            }
        }
    });

    return messages.count > 0 ? messages : nil;
}

#pragma mark - NSCoding

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:self.snowflake         forKey:@"snowflake"];
    [aCoder encodeObject:self.parentID          forKey:@"parentID"];
    [aCoder encodeObject:self.name              forKey:@"name"];
    [aCoder encodeObject:self.lastMessageId     forKey:@"lastMessageId"];
    [aCoder encodeObject:self.lastReadMessageId forKey:@"lastReadMessageId"];
    [aCoder encodeInteger:self.mentionCount     forKey:@"mentionCount"];
    [aCoder encodeBool:self.muted               forKey:@"muted"];
    [aCoder encodeBool:self.writeable           forKey:@"writeable"];
    [aCoder encodeInteger:self.type             forKey:@"type"];
    [aCoder encodeInteger:self.position         forKey:@"position"];

    // For DM channels: encode recipient display names only (no full DCUser graph)
    NSMutableArray *recipientNames = [NSMutableArray array];
    for (id recipient in self.recipients) {
        if ([recipient respondsToSelector:@selector(displayName)]) {
            NSString *name = [recipient displayName];
            if (name) [recipientNames addObject:name];
        }
    }
    [aCoder encodeObject:recipientNames forKey:@"recipientNames"];
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {
        self.snowflake         = [aDecoder decodeObjectForKey:@"snowflake"];
        self.parentID          = [aDecoder decodeObjectForKey:@"parentID"];
        self.name              = [aDecoder decodeObjectForKey:@"name"];
        self.lastMessageId     = [aDecoder decodeObjectForKey:@"lastMessageId"];
        self.lastReadMessageId = [aDecoder decodeObjectForKey:@"lastReadMessageId"];
        self.mentionCount      = [aDecoder decodeIntegerForKey:@"mentionCount"];
        self.muted             = [aDecoder decodeBoolForKey:@"muted"];
        self.writeable         = [aDecoder decodeBoolForKey:@"writeable"];
        self.type              = (DCChannelType)[aDecoder decodeIntegerForKey:@"type"];
        self.position          = [aDecoder decodeIntegerForKey:@"position"];
        // recipientNames decoded but not used yet — full recipient objects
        // come from the live READY payload. Channel name is sufficient for display.
    }
    return self;
}

@end
