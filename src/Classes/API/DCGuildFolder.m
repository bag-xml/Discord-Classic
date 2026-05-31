//
//  DCGuildFolder.m
//  Discord Classic
//
//  Created by plx on 7/13/25.
//  Copyright (c) 2025 plzdonthaxme. All rights reserved.
//

#import "DCGuildFolder.h"

@implementation DCGuildFolder

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:self.name    forKey:@"name"];
    [aCoder encodeInteger:self.color  forKey:@"color"];
    [aCoder encodeInteger:self.id     forKey:@"id"];
    [aCoder encodeObject:self.guildIds forKey:@"guildIds"];
    [aCoder encodeBool:self.opened    forKey:@"opened"];
    // icon deliberately excluded — no UIImage in cache
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {
        self.name     = [aDecoder decodeObjectForKey:@"name"];
        self.color    = [aDecoder decodeIntegerForKey:@"color"];
        self.id       = [aDecoder decodeIntegerForKey:@"id"];
        self.guildIds = [aDecoder decodeObjectForKey:@"guildIds"];
        self.opened   = [aDecoder decodeBoolForKey:@"opened"];
    }
    return self;
}

@end
