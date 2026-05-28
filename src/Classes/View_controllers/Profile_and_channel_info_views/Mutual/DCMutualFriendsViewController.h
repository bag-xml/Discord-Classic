//
//  DCMutualFriendsViewController.h
//  Discord Classic
//
//  Created by XML on 04/01/25.
//  Copyright (c) 2025 bag.xml. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DCContactViewController.h"
#import "DCRecipientTableCell.h"
#import "DCTools.h"
#import "DCUser.h"

@interface DCMutualFriendsViewController
    : UIViewController<UITableViewDelegate, UITableViewDataSource>
@property (strong, nonatomic) DCUser *user;
@property (strong, nonatomic) DCUser *selectedUser;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *doneButton;
@property (weak, nonatomic) IBOutlet UINavigationBar *titleBar;
@property (weak, nonatomic) IBOutlet UITableView *mutTableView;

// Holds NSDictionary*
@property (strong, nonatomic) NSArray *mutualFriendsList;
// Holds DCUser*
@property (strong, nonatomic) NSMutableArray *recipients;
@end
