//
//  DCMessage.h
//  Discord Classic
//
//  Created by bag.xml on 4/6/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <objc/NSObjCRuntime.h>
#import <UIKit/UIKit.h>
#import "DCTools.h"
#import "DCUser.h"

typedef NS_ENUM(NSInteger, DCMessageType) {
    DCMessageTypeDefault                                 = 0,
    DCMessageTypeRecipientAdd                            = 1,
    DCMessageTypeRecipientRemove                         = 2,
    DCMessageTypeCall                                    = 3,
    DCMessageTypeChannelNameChange                       = 4,
    DCMessageTypeChannelIconChange                       = 5,
    DCMessageTypeChannelPinnedMessage                    = 6,
    DCMessageTypeUserJoin                                = 7,
    DCMessageTypeGuildBoost                              = 8,
    DCMessageTypeGuildBoostTier1                         = 9,
    DCMessageTypeGuildBoostTier2                         = 10,
    DCMessageTypeGuildBoostTier3                         = 11,
    DCMessageTypeChannelFollowAdd                        = 12,
    DCMessageTypeGuildDiscoveryDisqualified              = 14,
    DCMessageTypeGuildDiscoveryRequalified               = 15,
    DCMessageTypeGuildDiscoveryGracePeriodInitialWarning = 16,
    DCMessageTypeGuildDiscoveryGracePeriodFinalWarning   = 17,
    DCMessageTypeThreadCreated                           = 18,
    DCMessageTypeReply                                   = 19,
    DCMessageTypeChatInputCommand                        = 20,
    DCMessageTypeThreadStarterMessage                    = 21,
    DCMessageTypeGuildInviteReminder                     = 22,
    DCMessageTypeContextMenuCommand                      = 23,
    DCMessageTypeAutoModerationAction                    = 24,
    DCMessageTypeRoleSubscriptionPurchase                = 25,
    DCMessageTypeInteractionPremiumUpsell                = 26,
    DCMessageTypeStageStart                              = 27,
    DCMessageTypeStageEnd                                = 28,
    DCMessageTypeStageSpeaker                            = 29,
    DCMessageTypeStageTopic                              = 31,
    DCMessageTypeGuildApplicationPremiumSubscription     = 32,
    DCMessageTypeGuildIncidentAlertModeEnabled           = 36,
    DCMessageTypeGuildIncidentAlertModeDisabled          = 37,
    DCMessageTypeGuildIncidentReportRaid                 = 38,
    DCMessageTypeGuildIncidentReportFalseAlarm           = 39,
    DCMessageTypePurchaseNotification                    = 44,
    DCMessageTypePollResult                              = 46,
};

typedef NS_ENUM(NSInteger, DCMessageReferenceType) {
    DCMessageReferenceTypeDefault = 0, // + referenced_message
    DCMessageReferenceTypeForward = 1, // + message_snapshot
};

@interface DCMessage : NSObject
@property (strong, nonatomic) DCSnowflake* snowflake;
@property (strong, nonatomic) DCUser* author;
@property (strong, nonatomic) NSString* content;
@property (strong, nonatomic) NSAttributedString* attributedContent;
@property (assign, nonatomic) NSInteger attachmentCount;
@property (strong, nonatomic) NSMutableArray* attachments;
@property (assign, nonatomic) NSInteger contentHeight;
@property (assign, nonatomic) NSInteger authorNameWidth;
@property (strong, nonatomic) NSDate* timestamp;
@property (strong, nonatomic) NSDate* editedTimestamp;
@property (strong, nonatomic) NSString* prettyTimestamp;
@property (assign, nonatomic) BOOL pingingUser;
@property (assign, nonatomic) BOOL isGrouped;
@property (strong, nonatomic) NSString* preDefinedContent;
@property (assign, nonatomic) NSInteger messageType;
@property (strong, nonatomic) DCMessage* referencedMessage;
@property (strong, nonatomic) NSMutableArray* emojis;

// embed
//@property NSString *
- (void)deleteMessage;
- (BOOL)isEqual:(id)other;
@end
