#import "DCTools.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface DCRole : NSObject

@property (strong, nonnull) DCSnowflake* snowflake;
@property (strong, nonnull) NSString* name;
@property (assign, nonatomic) NSInteger color;
// colors
@property (assign, nonatomic) BOOL hoist;
@property (strong, nullable, nonatomic) DCSnowflake* iconID;
@property (strong, nullable, nonatomic) UIImage* icon;
@property (strong, nullable, nonatomic) NSString* unicodeEmoji;
@property (assign, nonatomic) NSInteger position;
@property (strong, nonnull, nonatomic) NSString* permissions;
@property (assign, nonatomic) BOOL managed;
@property (assign, nonatomic) BOOL mentionable;
// tags
@property (assign, nonatomic) NSInteger flags;

- (NSString* _Nonnull)description;

@end