//
//  DCContactViewController.h
//  Discord Classic
//
//  Created by bag.xml on 27/01/24.
//  Copyright (c) 2024 bag.xml. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "APLSlideMenuViewController.h"
#import "DCConnectedAccountsCell.h"
#import "DCMutualFriendsViewController.h"
#import "DCServerCommunicator.h"
#import "DCTools.h"
#import "DCUser.h"
#import "UIColorHex.h"
@interface DCContactViewController
    : UIViewController<UITableViewDelegate, UITableViewDataSource>

- (void)setSelectedUser:(DCUser *)user;

@property (weak, nonatomic) IBOutlet UINavigationBar *navBar;
@property (weak, nonatomic) IBOutlet UITableView *conTableView;
@property (weak, nonatomic) IBOutlet UILabel *pronounLabel;
@property (weak, nonatomic) IBOutlet UIButton *chatButton;
@property (weak, nonatomic) IBOutlet UIButton *mutualFriendsButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *doneButton;

@property bool noConnections;
@property NSString *snowflake;
@property NSDictionary *connectedAccounts;
@property NSArray *mutualFriends;
@property NSDictionary *mutualGuilds;
@end
