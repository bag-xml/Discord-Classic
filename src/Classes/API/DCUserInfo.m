#include "DCUserInfo.h"

@implementation DCUserInfo

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:self.username        forKey:@"username"];
    [aCoder encodeObject:self.globalName      forKey:@"globalName"];
    [aCoder encodeObject:self.id              forKey:@"id"];
    [aCoder encodeObject:self.avatar          forKey:@"avatar"];
    [aCoder encodeObject:self.guildPositions  forKey:@"guildPositions"];
    [aCoder encodeObject:self.guildFolders    forKey:@"guildFolders"];
    // Sensitive fields (phone, email) deliberately not cached
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {
        self.username       = [aDecoder decodeObjectForKey:@"username"];
        self.globalName     = [aDecoder decodeObjectForKey:@"globalName"];
        self.id             = [aDecoder decodeObjectForKey:@"id"];
        self.avatar         = [aDecoder decodeObjectForKey:@"avatar"];
        self.guildPositions = [aDecoder decodeObjectForKey:@"guildPositions"];
        self.guildFolders   = [aDecoder decodeObjectForKey:@"guildFolders"];
    }
    return self;
}

@end