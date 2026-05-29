//
//  DCIntroductionPage.h
//  Discord Classic
//
//  Created by bag.xml on 28/01/24.
//  Copyright (c) 2024 bag.xml. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DCServerCommunicator.h"

@interface DCIntroductionPage : UITableViewController<UITextFieldDelegate>

@property (weak, nonatomic) IBOutlet UITextField *tokenInputField;
@property (weak, nonatomic) IBOutlet UIButton *loginButton;

@property (assign, nonatomic) BOOL authenticated;

@end
