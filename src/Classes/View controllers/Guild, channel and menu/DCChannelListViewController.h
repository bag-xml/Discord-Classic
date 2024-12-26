//
//  DCChannelViewController.h
//  Discord Classic
//
//  Created by Julian Triveri on 3/5/18.
//  Copyright (c) 2018 Julian Triveri. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DCGuild.h"

@interface DCChannelListViewController : UITableViewController <UIAlertViewDelegate>
@property DCGuild* selectedGuild;

@end
