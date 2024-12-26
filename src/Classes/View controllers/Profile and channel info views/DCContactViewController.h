//
//  DCContactViewController.h
//  Discord Classic
//
//  Created by bag.xml on 27/01/24.
//  Copyright (c) 2024 Julian Triveri. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DCUser.h"
#import "DCTools.h"
#import "DCServerCommunicator.h"

@interface DCContactViewController : UITableViewController

-(void)setSelectedUser:(DCUser*)user;
-(void)requestProfileInformation:(DCUser*)user;

@property (weak, nonatomic) IBOutlet UIButton *chatButton;
@property NSString* snowflake;
@end
