//
//  DCGuild.m
//  Discord Classic
//
//  Created by Julian Triveri on 3/12/18.
//  Copyright (c) 2018 Julian Triveri. All rights reserved.
//

#import "DCGuild.h"
#import "DCChannel.h"

@implementation DCGuild

-(NSString *)description{
	return [NSString stringWithFormat:@"[Guild] Snowflake: %@, Read: %d, Name: %@, Channels: %@", self.snowflake, self.unread, self.name, self.channels];
}

-(void)checkIfRead{
	/*Loop through all child channels
	 if any single one is unread, the guild
	 as a whole is unread*/
	for(DCChannel* channel in self.channels){
		if(channel.unread){
			self.unread = true;
			return;
		}
	}
	
	[self setUnread:false];
}

@end
