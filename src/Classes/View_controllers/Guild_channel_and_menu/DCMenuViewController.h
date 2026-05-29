//
//  DCMenuViewController.h
//  Discord Classic
//
//  Created by bag.xml on 27/01/24.
//  Copyright (c) 2024 bag.xml. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DCCInfoViewController.h"
#import "DCChannel.h"
#import "DCChannelViewCell.h"
#import "DCChatViewController.h"
#import "DCGuild.h"
#import "DCGuildTableViewCell.h"
#import "DCOwnAccountInfoManagementController.h"
#import "DCPrivateChannelTableCell.h"
#import "DCServerCommunicator.h"
#import "DCTools.h"
#import "DCUser.h"
#import "CKRefreshControl.h"

#define VERSION_MIN(v)                                                  \
    ([[[UIDevice currentDevice] systemVersion] compare:v                \
                                               options:NSNumericSearch] \
     != NSOrderedAscending)

@interface DCMenuViewController : UIViewController<
                                      UITableViewDelegate,
                                      UITableViewDataSource,
                                      UIActionSheetDelegate>

@property (weak, nonatomic) IBOutlet UITableView *guildTableView;
@property (weak, nonatomic) IBOutlet UITableView *channelTableView;
@property (strong, nonatomic) DCGuild *selectedGuild;
@property (strong, nonatomic) DCChannel *selectedChannel;
@property (strong, nonatomic) UIRefreshControl *refreshControl;
@property (strong, nonatomic) UIRefreshControl *reloadControl;
@property (weak, nonatomic) IBOutlet UIToolbar *toolbar;
@property (weak, nonatomic) IBOutlet UILabel *guildLabel;
@property (weak, nonatomic) IBOutlet UIImageView *guildBanner;

@property (strong, nonatomic) UIImage *dmIcon; // Icon for a DM
@property (weak, nonatomic) IBOutlet UILabel *userName;
@property (weak, nonatomic) IBOutlet UILabel *globalName;

@property (weak, nonatomic) IBOutlet UIView *totalView;

@property (weak, nonatomic) IBOutlet UIView *guildTotalView;


@property BOOL experimentalMode;
@property NSOperationQueue *serverIconImageQueue;

+ (NSString *)imageNameForStatus:(DCUserStatus)status;

@end
