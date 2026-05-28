#import <Foundation/Foundation.h>
#import "DCTools.h"

@interface DCUserInfo : NSObject

@property (strong, nonatomic) NSString* username;
@property (strong, nonatomic) NSString* globalName;
@property (strong, nonatomic) NSString* pronouns;
@property (strong, nonatomic) DCSnowflake* avatar;
@property (strong, nonatomic) NSString* phone;
@property (strong, nonatomic) NSString* email;
@property (strong, nonatomic) NSString* bio;
@property (strong, nonatomic) DCSnowflake* banner;
@property (strong, nonatomic) NSString* bannerColor;
@property (strong, nonatomic) NSString* clan;
@property (strong, nonatomic) DCSnowflake* id;
@property (strong, nonatomic) NSMutableDictionary* connectedAccounts;
@property (strong, nonatomic) NSMutableArray* guildPositions;
@property (strong, nonatomic) NSMutableArray* guildFolders;

@end