#import "DCRole.h"

@implementation DCRole

- (NSString *)description {
    return [NSString
        stringWithFormat:@"[Role] Snowflake: %@, Name: %@, Color: %ld, Hoist: %d, Unicode Emoji: %@, Position: %ld, Permissions: %@, Managed: %d, Mentionable: %d, Flags: %ld",
                         self.snowflake,
                         self.name,
                         (long)self.color,
                         self.hoist,
                         self.unicodeEmoji,
                         (long)self.position,
                         self.permissions,
                         self.managed,
                         self.mentionable,
                         (long)self.flags];
}
@end
