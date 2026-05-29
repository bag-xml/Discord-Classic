//
//  DCGuild.h
//  Discord Classic
//
//  Created by bag.xml on 3/12/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

/*DCGuild is a representation of a Discord API Guild object.
 Its easier to work with than raw JSON data and has some handy
 built in functions*/

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "DCTools.h"

@interface DCGuild : NSObject
// ID/snowflake
@property (strong, nonatomic) DCSnowflake* snowflake;
// Name
@property (strong, nonatomic) NSString* name;
// The ID of the guild's owner
@property (strong, nonatomic) DCSnowflake* ownerID;
// The number of members in the guild
@property (assign, nonatomic) NSInteger memberCount;
// The number of currently online members in the guild
@property (assign, nonatomic) NSInteger onlineCount;
// Whether it is muted
@property (assign, nonatomic) BOOL muted;

// The guild's icon
@property (strong, nonatomic) UIImage* icon;
// The guild's banner
@property (strong, nonatomic) UIImage* banner;

// Array of child DCChannel objects
@property (strong, nonatomic) NSMutableArray* channels;
// Whether or not the guild has any unread child channels
@property (assign, nonatomic) BOOL unread;
// Members of the guild for display (can contain roles)
@property (strong, nonatomic) NSMutableArray* members;
// Roles in the guild
@property (strong, nonatomic) NSMutableDictionary* roles;
// Array of the current user's roles in the guild
@property (strong, nonatomic) NSMutableArray* userRoles;
// Emojis in the guild
@property (strong, nonatomic) NSMutableDictionary* emojis;

- (void)checkIfRead;
@end
