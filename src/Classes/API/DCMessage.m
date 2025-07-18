//
//  DCMessage.m
//  Discord Classic
//
//  Created by bag.xml on 4/7/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import "DCMessage.h"
#import "DCServerCommunicator.h"
#import "DCTools.h"

@implementation DCMessage

static dispatch_queue_t messages_delete_queue;
- (dispatch_queue_t)get_messages_delete_queue {
    if (messages_delete_queue == nil) {
        messages_delete_queue = dispatch_queue_create(
            [@"Discord::API::Message::Delete" UTF8String],
            DISPATCH_QUEUE_CONCURRENT
        );
    }
    return messages_delete_queue;
}

- (void)deleteMessage {
    dispatch_async([self get_messages_delete_queue], ^{
        NSURL *messageURL = [NSURL
            URLWithString:[NSString
                              stringWithFormat:@"https://discordapp.com/api/v9/"
                                               @"channels/%@/messages/%@",
                                               DCServerCommunicator
                                                   .sharedInstance
                                                   .selectedChannel.snowflake,
                                               self.snowflake]];

        NSMutableURLRequest *urlRequest = [NSMutableURLRequest
             requestWithURL:messageURL
                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
            timeoutInterval:10];
        [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];
        [urlRequest setHTTPMethod:@"DELETE"];
        [urlRequest addValue:DCServerCommunicator.sharedInstance.token
            forHTTPHeaderField:@"Authorization"];
        [urlRequest addValue:@"application/json"
            forHTTPHeaderField:@"Content-Type"];

        dispatch_sync(dispatch_get_main_queue(), ^{
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
    });
}

- (BOOL)isEqual:(id)other {
    if (!other || ![other isKindOfClass:DCMessage.class]) {
        return NO;
    }

    return [self.snowflake isEqual:((DCMessage *)other).snowflake];
}

@end
