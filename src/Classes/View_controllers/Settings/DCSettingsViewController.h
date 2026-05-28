//
//  DCSettingsViewController.h
//  Discord Classic
//
//  Created by Trevir on 3/18/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DCSettingsViewController : UITableViewController

@property (weak, nonatomic) IBOutlet UITextField *tokenInputField;
@property (weak, nonatomic) IBOutlet UISwitch *experimentalToggle;
@property (weak, nonatomic) IBOutlet UISwitch *dataSaverToggle;

@property (assign, nonatomic) BOOL isLoggingOut;
- (IBAction)didTapLogOut;

@end
