//
//  DCUser.h
//  Discord Classic
//
//  Created by Trevir on 11/17/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <objc/NSObjCRuntime.h>
#import <UIKit/UIKit.h>
#import "DCTools.h"

typedef NS_ENUM(NSInteger, DCUserStatus) {
    DCUserStatusOnline,
    DCUserStatusIdle,
    DCUserStatusDoNotDisturb,
    DCUserStatusOffline
};

@interface DCUser : NSObject
@property (strong, nonatomic) DCSnowflake* snowflake;
@property (strong, nonatomic) NSString* username;
@property (strong, nonatomic) NSString* globalName;
@property (strong, nonatomic) NSString* biography;
@property (strong, nonatomic) NSString* customStatus;
@property (assign, nonatomic) DCUserStatus status;
@property (strong, nonatomic) DCSnowflake* avatarID;
@property (strong, nonatomic) DCSnowflake* avatarDecorationID;
@property (strong, nonatomic) UIImage* profileImage;
@property (strong, nonatomic) UIImage* profileBanner;
@property (assign, nonatomic) NSInteger discriminator;
@property (strong, nonatomic) UIImage* avatarDecoration;

+ (DCUserStatus)statusFromString:(NSString *)statusString;
+ (NSString *)stringFromStatus:(DCUserStatus)status;
+ (NSArray*)defaultAvatars;
- (NSString*)description;
@end
