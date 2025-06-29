//
//  DCMessage.h
//  Discord Classic
//
//  Created by bag.xml on 4/6/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
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
@property NSString* preDefinedContent;
@property int messageType;
@property DCMessage* referencedMessage;

// embed
//@property NSString *
- (void)deleteMessage;
- (BOOL)isEqual:(id)other;
@end
