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
#include <UIKit/UIKit.h>

@interface DCGuild : NSObject
// ID/snowflake
@property NSString* snowflake;
// Name
@property NSString* name;
// The ID of the guild's owner
@property NSString* ownerID;
// The number of members in the guild
@property int memberCount;

// The guild's icon
@property UIImage* icon;
// The guild's banner
@property UIImage* banner;

// Array of child DCChannel objects
@property NSMutableArray* channels;
// Whether or not the guild has any unread child channels
@property bool unread;
// Members of the guild (currently unimplemented)
@property NSMutableArray* members;
// Roles in the guild
@property NSMutableDictionary* roles;
// Array of the current user's roles in the guild
@property NSMutableArray* userRoles;

- (void)checkIfRead;
@end
