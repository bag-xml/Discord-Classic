//
//  DCIntroductionPage.h
//  Discord Classic
//
//  Created by bag.xml on 28/01/24.
//  Copyright (c) 2024 bag.xml. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DCServerCommunicator.h"

@interface DCIntroductionPage : UITableViewController <UITextFieldDelegate>

// Storyboard outlets — replace the old tokenInputField with these two.
@property (weak, nonatomic) IBOutlet UITextField *emailField;
@property (weak, nonatomic) IBOutlet UITextField *passwordField;
@property (strong, nonatomic) IBOutlet UIBarButtonItem *loginButton;
@property (strong, nonatomic) UIBarButtonItem *spinnerItem;
@property (weak, nonatomic) IBOutlet UIImageView *backgroundField;
@property (weak, nonatomic) IBOutlet UIButton *buttonToken;

@property (assign, nonatomic) BOOL authenticated;


- (IBAction)didClickLoginButton;

- (void)didLogin;

@end
