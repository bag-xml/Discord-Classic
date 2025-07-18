//
//  DCGuild.m
//  Discord Classic
//
//  Created by bag.xml on 3/12/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import "DCGuild.h"
#import "DCChannel.h"

@implementation DCGuild

- (NSString*)description {
    return [NSString
        stringWithFormat:
            @"[Guild] Snowflake: %@, Read: %d, Name: %@, Channels: %@",
            self.snowflake, self.unread, self.name, self.channels];
}

- (void)checkIfRead {
    BOOL oldUnread = self.unread;
    if (self.muted) {
        self.unread = false;
        goto refreshMarker;
    }
    /*Loop through all child channels
     if any single one is unread, the guild
     as a whole is unread*/
    for (DCChannel* channel in self.channels) {
        if (channel.unread) {
            self.unread = true;
            goto refreshMarker;
        }
    }
    self.unread = false;
refreshMarker:
    if (self.unread != oldUnread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter
                postNotificationName:@"RELOAD GUILD"
                              object:self];
        });
    }
}

@end
