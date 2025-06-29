#import "DCRole.h"

@implementation DCRole

- (NSString *)description {
    return [NSString
        stringWithFormat:@"[Role] Snowflake: %@, Name: %@, Color: %d, Hoist: %d, Icon: %@, Unicode Emoji: %@, Position: %d, Permissions: %@, Managed: %d, Mentionable: %d, Flags: %d",
                         self.snowflake,
                         self.name,
                         self.color,
                         self.hoist,
                         self.icon,
                         self.unicodeEmoji,
                         self.position,
                         self.permissions,
                         self.managed,
                         self.mentionable,
                         self.flags];
}
@end
