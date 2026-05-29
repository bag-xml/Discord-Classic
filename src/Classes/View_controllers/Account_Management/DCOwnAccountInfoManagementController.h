//
//  DCOwnAccountInfoManagementController.h
//  Discord Classic
//
//  Created by XML on 03/01/25.
//  Copyright (c) 2025 bag.xml. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DCConnectedAccountsCell.h"
#import "DCServerCommunicator.h"
#import "UIColorHex.h"

@interface DCOwnAccountInfoManagementController : UITableViewController
@property (weak, nonatomic) IBOutlet UIBarButtonItem *doneButton;

@property (weak, nonatomic) IBOutlet UIImageView *pfp;
@property (weak, nonatomic) IBOutlet UIImageView *banner;

@property (weak, nonatomic) IBOutlet UIView *bannerView;

@property (weak, nonatomic) IBOutlet UILabel *pronouns;
@property (weak, nonatomic) IBOutlet UILabel *username;
@property (weak, nonatomic) IBOutlet UILabel *trueusername;

@property (weak, nonatomic) IBOutlet UITextView *bio;

@property (weak, nonatomic) IBOutlet UILabel *email;
@property (weak, nonatomic) IBOutlet UILabel *phoneNumber;
@property (weak, nonatomic) IBOutlet UILabel *userID;
@property (weak, nonatomic) IBOutlet UILabel *token;

@property (strong, nonatomic) NSDictionary *activeConnections;
@property (assign, nonatomic) BOOL noConnections;

@end
