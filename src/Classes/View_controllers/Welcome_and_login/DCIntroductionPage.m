//
//  DCIntroductionPage.m
//  Discord Classic
//
//  Created by bag.xml on 28/01/24.
//  Copyright (c) 2024 bag.xml. All rights reserved.
//

#import "DCIntroductionPage.h"
#import "DCAppDelegate.h"
#import "DCLoginManager.h"
#import "DCTokenLoginPage.h"
#import "APLSlideMenuViewController.h"
#import "DCTwoFactorViewController.h"

@interface DCIntroductionPage ()

// Held across the 2FA step.
@property (strong, nonatomic) NSString *pendingTwoFactorTicket;

// Loading indicator shown during network requests.
@property (strong, nonatomic) UIActivityIndicatorView *spinner;

@end

@implementation DCIntroductionPage

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
    }
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations {
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

#pragma mark - Lifecycle

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.authenticated = NO;
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"experimentalMode"]) {
        [self.navigationController.navigationBar
         setBackgroundImage:[UIImage imageNamed:@"TbarBG"]
         forBarMetrics:UIBarMetricsDefault];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.hidesBackButton     = YES;
    self.slideMenuController.gestureSupport = NO;
    self.emailField.delegate                = self;
    self.passwordField.delegate             = self;
    
    // Set background color fix for iOS 5
    self.tableView.backgroundView = nil;
    self.tableView.backgroundColor = [UIColor colorWithRed:40/255.0f green:41/255.0f blue:46/255.0f alpha:1.0f];
    self.view.backgroundColor = [UIColor colorWithRed:40/255.0f green:41/255.0f blue:46/255.0f alpha:1.0f];

    // Create a button sized to the bar button item
    [self.loginButton setBackgroundImage:[UIImage imageNamed:@"BarButtonDone"]
                               forState:UIControlStateNormal
                             barMetrics:UIBarMetricsDefault];
    [self.loginButton setBackgroundImage:[UIImage imageNamed:@"BarButtonDonePressed"]
                               forState:UIControlStateHighlighted
                             barMetrics:UIBarMetricsDefault];
    
    // Message Input bitmap
    UIImage *img = [UIImage imageNamed:@"MessageField"];
    UIEdgeInsets caps = UIEdgeInsetsMake(15, 15, 15, 15);
    
    UIImage *stretch;
    if ([img respondsToSelector:@selector(resizableImageWithCapInsets:resizingMode:)]) {
        stretch = [img resizableImageWithCapInsets:caps resizingMode:UIImageResizingModeStretch];
    } else {
        stretch = [img stretchableImageWithLeftCapWidth:15 topCapHeight:15];
    }
    
    self.backgroundField.image = stretch;
    
    // Spinner styling
    UIView *spinnerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 52, 30)];
    
    UIImageView *bgImageView = [[UIImageView alloc] initWithFrame:spinnerContainer.bounds];
    UIImage *btnImage = [UIImage imageNamed:@"BarButtonDone"];
    UIEdgeInsets insets = UIEdgeInsetsMake(0, 5, 0, 5);
    UIImage *stretchedBg;
    if ([btnImage respondsToSelector:@selector(resizableImageWithCapInsets:resizingMode:)]) {
        stretchedBg = [btnImage resizableImageWithCapInsets:insets resizingMode:UIImageResizingModeStretch];
    } else {
        stretchedBg = [btnImage stretchableImageWithLeftCapWidth:5 topCapHeight:0];
    }
    bgImageView.image = stretchedBg;
    [spinnerContainer addSubview:bgImageView];
    
    self.spinner = [[UIActivityIndicatorView alloc]
                    initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.center = CGPointMake(spinnerContainer.bounds.size.width / 2,
                                      spinnerContainer.bounds.size.height / 2);
    [spinnerContainer addSubview:self.spinner];
    self.spinnerItem = [[UIBarButtonItem alloc] initWithCustomView:spinnerContainer];
    
    DCAppDelegate *appDelegate = (DCAppDelegate *)[UIApplication sharedApplication].delegate;
    if (appDelegate.loggingOut) {
        appDelegate.loggingOut = NO;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.emailField becomeFirstResponder];
        });
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.emailField becomeFirstResponder];
        });
    }

}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.emailField) {
        [self.passwordField becomeFirstResponder];
    } else {
        [textField resignFirstResponder];
        [self didClickLoginButton];
    }
    return YES;
}

#pragma mark - Login

- (IBAction)didClickLoginButton {
    NSString *email    = [self.emailField.text stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceCharacterSet]];
    NSString *password = self.passwordField.text;

    if (email.length == 0 || password.length == 0) {
        [self showAlertWithTitle:@"Missing fields"
                         message:@"Please enter your email and password."];
        return;
    }

    [self setLoading:YES];

    [DCLoginManager loginWithEmail:email
                          password:password
                        completion:^(NSString *token, NSError *error) {
        [self setLoading:NO];

        if (token) {
            [self completeLoginWithToken:token];
            return;
        }

        if (error.code == DCLoginErrorCodeTwoFactor) {
            self.pendingTwoFactorTicket =
                error.userInfo[DCLoginErrorTwoFactorTicketKey];
            NSLog(@"[2FA] ticket: %@", error.userInfo[DCLoginErrorTwoFactorTicketKey]);
            NSLog(@"[2FA] fingerprint: %@", error.userInfo[DCLoginErrorFingerprintKey]);
            [self performSegueWithIdentifier:@"show2FA" sender:@{
                                                                 @"ticket"     : error.userInfo[DCLoginErrorTwoFactorTicketKey],
                                                                 @"fingerprint": error.userInfo[DCLoginErrorFingerprintKey],
                                                                 @"instanceID" : error.userInfo[DCLoginErrorInstanceIDKey] ?: @""
                                                                 }];
            return;
        }

        if (error.code == DCLoginErrorCodeCaptcha) {
                    [self showAlertWithTitle:@"Are you a robot?"
                                     message:@"Complete the captcha on a modern device, "
                                              "using the same network, then try logging in again."];
                    return;
                }
                NSInteger discordCode = [error.userInfo[@"discord_code"] integerValue];
                if (discordCode == 50035) {
                    [self showAlertWithTitle:@"Login Failed"
                                     message:@"Invalid email or password. Please check your credentials and try again."];
                    return;
                }
                if (discordCode == 10004) {
                    [self showAlertWithTitle:@"Account Not Found"
                                     message:@"No account was found with this email address."];
                    return;
                }
                if (discordCode == 20016) {
                    [self showAlertWithTitle:@"Verification Required"
                                     message:@"Your account needs to be verified. Please check your email and verify your account before logging in."];
                    return;
                }
                if (discordCode == 40002) {
                    [self showAlertWithTitle:@"Verification Required"
                                     message:@"Your account requires phone verification. Please complete this on a modern Discord client first."];
                    return;
                }
        NSString *message = error.userInfo[DCLoginErrorServerMessageKey]
            ?: error.localizedDescription
            ?: @"Login failed. Please check your credentials.";
        [self showAlertWithTitle:@"Login Failed" message:message];
    }];
}


- (void)completeLoginWithToken:(NSString *)token {
    [NSUserDefaults.standardUserDefaults setObject:token forKey:@"token"];
    [NSUserDefaults.standardUserDefaults synchronize];
    DCServerCommunicator.sharedInstance.token = token;
    [DCServerCommunicator.sharedInstance reconnect];
    [self didLogin];
}

- (void)didLogin {
    self.authenticated = YES;
    [self performSegueWithIdentifier:@"login to guilds" sender:self];
    // Remove intro page from nav stack so back button can't return to it.
    NSMutableArray *stack = [self.navigationController.viewControllers mutableCopy];
    [stack removeObjectAtIndex:0];
    self.navigationController.viewControllers = stack;
}


#pragma mark - Helpers

- (void)setLoading:(BOOL)loading {
    self.loginButton.enabled = !loading;
    if (loading) {
        [self.spinner startAnimating];
        self.navigationItem.rightBarButtonItem = self.spinnerItem;
    } else {
        [self.spinner stopAnimating];
        self.navigationItem.rightBarButtonItem = self.loginButton;
    }
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                    message:message
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];
}

#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"show2FA"]) {
        DCTwoFactorViewController *vc = segue.destinationViewController;
        NSDictionary *info = sender;
        vc.twoFactorTicket      = info[@"ticket"];
        vc.twoFactorFingerprint = info[@"fingerprint"];
        vc.twoFactorInstanceID = info[@"instanceID"];
        vc.completionBlock = ^(NSString *token) {
            [self completeLoginWithToken:token];
        };
    }
    if ([segue.identifier isEqualToString:@"showToken"]) {
        DCTokenLoginPage *vc = segue.destinationViewController;
        vc.introPage = self;
    }
}

@end
