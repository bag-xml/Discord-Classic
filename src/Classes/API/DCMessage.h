//
//  DCMessage.h
//  Discord Classic
//
//  Created by Julian Triveri on 4/6/18.
//  Copyright (c) 2018 Julian Triveri. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DCUser.h"

@interface DCMessage : NSObject
@property NSString* snowflake;
@property DCUser* author;
@property NSString* content;
@property int attachmentCount;
@property NSMutableArray* attachments;
@property int contentHeight;
@property int authorNameWidth;
@property NSDate* timestamp;
@property NSDate* editedTimestamp;
@property NSString* prettyTimestamp;
@property bool pingingUser;
@property bool isGrouped;
@property bool missedCall;
@property DCMessage* referencedMessage;

- (void)deleteMessage;
- (BOOL)isEqual:(id)other;
@end
