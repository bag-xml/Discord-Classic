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
@interface ODCContactViewController : UITableViewController

- (void)setSelectedUser:(DCUser*)user;

@property (weak, nonatomic) IBOutlet UILabel* pronounLabel;
@property (weak, nonatomic) IBOutlet UIButton* chatButton;
@property (weak, nonatomic) IBOutlet UIButton* mutualFriendsButton;

@property (assign, nonatomic) BOOL noConnections;
@property (strong, nonatomic) NSString* snowflake;
@property (strong, nonatomic) NSDictionary* connectedAccounts;
@property (strong, nonatomic) NSArray* mutualFriends;
@property (strong, nonatomic) NSDictionary* mutualGuilds;
@end
