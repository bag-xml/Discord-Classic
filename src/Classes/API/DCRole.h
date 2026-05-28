#import "DCTools.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface DCRole : NSObject

@property (strong, nonatomic) DCSnowflake* snowflake;
@property (strong, nonatomic) NSString* name;
@property (assign, nonatomic) NSInteger color;
@property (assign, nonatomic) BOOL hoist;
@property (strong, nonatomic) DCSnowflake* iconID;
@property (strong, nonatomic) UIImage* icon;
@property (strong, nonatomic) NSString* unicodeEmoji;
@property (assign, nonatomic) NSInteger position;
@property (strong, nonatomic) NSString* permissions;
@property (assign, nonatomic) BOOL managed;
@property (assign, nonatomic) BOOL mentionable;
@property (assign, nonatomic) NSInteger flags;

- (NSString*)description;

@end