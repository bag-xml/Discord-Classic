//
//  DCTokenLoginPage.h
//  Discord Classic
//
//  Created by Ayeris on 2/28/26.
//  Copyright (c) 2026 bag.xml. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DCServerCommunicator.h"
#import "DCIntroductionPage.h"

@interface DCTokenLoginPage : UIViewController <UITextFieldDelegate>

@property (strong, nonatomic) IBOutlet UIBarButtonItem *buttonLogIn;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *buttonCancel;
@property (strong, nonatomic) UIBarButtonItem *spinnerItem;
@property (weak, nonatomic) IBOutlet UITextField *fieldToken;
@property (weak, nonatomic) IBOutlet UILabel *labelWarning;
@property (weak, nonatomic) IBOutlet UINavigationBar *navBar;

@property (weak, nonatomic) DCIntroductionPage *introPage;

- (IBAction)didTapLogIn;
- (IBAction)didTapCancel;

@end
