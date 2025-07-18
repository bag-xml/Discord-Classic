//
//  DCIntroductionPage.m
//  Discord Classic

//

//  Created by bag.xml on 28/01/24.
//  Copyright (c) 2024 bag.xml. All rights reserved.
//

#import "DCIntroductionPage.h"
#import "APLSlideMenuViewController.h"

@interface DCIntroductionPage ()

@end

@implementation DCIntroductionPage


- (void)viewWillAppear:(BOOL)animated {
    self.authenticated = false;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.hidesBackButton     = YES;
    self.slideMenuController.gestureSupport = NO;
    self.tokenInputField.delegate           = self;
    NSString *token =
        [NSUserDefaults.standardUserDefaults objectForKey:@"token"];

    if (token) {
        self.tokenInputField.text = token;
    } else {
        self.tokenInputField.text = UIPasteboard.generalPasteboard.string;
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (IBAction)didClickLoginButton {
    if (self.tokenInputField.text.length == 0) {
        [self showAlertWithTitle:@"Nothing..."
                         message:@"Make sure to properly type in your token."];
    } else {
        //[self.loginIndicator startAnimating];
        //[self.loginIndicator setHidden:false];
        [NSUserDefaults.standardUserDefaults setObject:self.tokenInputField.text
                                                forKey:@"token"];
        [[NSUserDefaults standardUserDefaults] synchronize];

        // Save the entered values and reauthenticate if the token has been
        // changed
        if (![DCServerCommunicator.sharedInstance.token
                isEqual:[NSUserDefaults.standardUserDefaults
                            objectForKey:@"token"]]) {
            DCServerCommunicator.sharedInstance.token =
                self.tokenInputField.text;
            [DCServerCommunicator.sharedInstance reconnect];
            [self didLogin];
        }
        [self.loginButton setHidden:true];
    }
}

- (void)didLogin {
    [self performSegueWithIdentifier:@"login to guilds" sender:self];
    self.authenticated = true;
    // user shouldn't be able to go back to this screen once logged in
    NSMutableArray *navigationArray = [[NSMutableArray alloc]
        initWithArray:self.navigationController.viewControllers];
    [navigationArray removeObjectAtIndex:0];
    self.navigationController.viewControllers = navigationArray;
}


- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:title
                                                        message:message
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
    [alertView show];
}
@end
