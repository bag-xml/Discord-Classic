//
//  DCGuild.h
//  Discord Classic
//
//  Created by Julian Triveri on 3/12/18.
//  Copyright (c) 2018 Julian Triveri. All rights reserved.
//

/*DCGuild is a representation of a Discord API Guild object.
 Its easier to work with than raw JSON data and has some handy 
 built in functions*/

#import <Foundation/Foundation.h>

@interface DCGuild : NSObject
//ID/snowflake
@property NSString* snowflake;
//Name
@property NSString* name;
//Icon and banner for the guild
@property UIImage* icon;
@property UIImage* banner;
//Array of child DCCannel objects
@property NSMutableArray* channels;
//Whether or not the guild has any unread child channels
@property bool unread;

@property NSMutableDictionary* members;

-(void)checkIfRead;
@end
