//
//  DCChannelViewController.h
//  Discord Classic
//
//  Created by bag.xml on 3/5/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DCGuild.h"

@interface DCChannelListViewController
    : UITableViewController<UIAlertViewDelegate>
@property DCGuild* selectedGuild;

@end
