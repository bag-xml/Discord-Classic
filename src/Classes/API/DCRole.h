#import <Foundation/Foundation.h>

@interface DCRole : NSObject

@property (nonnull) NSString* snowflake;
@property (nonnull) NSString* name;
@property int color;
// colors
@property bool hoist;
@property (nullable) UIImage* icon;
@property (nullable) NSString* unicodeEmoji;
@property int position;
@property (nonnull) NSString* permissions;
@property bool managed;
@property bool mentionable;
// tags
@property int flags;

- (NSString* _Nonnull)description;

@end