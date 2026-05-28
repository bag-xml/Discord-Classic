//
//  DCTwoFactorViewController.h
//  Discord Classic
//
//  Created by Ayeris on 2/28/26.
//  Copyright (c) 2026 bag.xml. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DCLoginManager.h"

@interface DCTwoFactorViewController : UIViewController <UITextFieldDelegate>

@property (strong, nonatomic) NSString *twoFactorTicket;
@property (strong, nonatomic) void (^completionBlock)(NSString *token);

@property (strong, nonatomic) IBOutlet UIBarButtonItem *buttonVerify;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *buttonCancel;
@property (strong, nonatomic) UIBarButtonItem *spinnerItem;
@property (weak, nonatomic) IBOutlet UITextField *fieldCode;
@property (weak, nonatomic) IBOutlet UILabel *labelWarning;
@property (weak, nonatomic) IBOutlet UINavigationBar *navBar;
@property (strong, nonatomic) NSString *twoFactorFingerprint;
@property (strong, nonatomic) NSString *twoFactorInstanceID;

- (IBAction)didTapVerify;
- (IBAction)didTapCancel;


@end
