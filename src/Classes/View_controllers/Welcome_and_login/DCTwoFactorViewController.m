//
//  DCTwoFactorViewController.m
//  Discord Classic
//
//  Created by Ayeris on 2/28/26.
//  Copyright (c) 2026 bag.xml. All rights reserved.
//

#import "DCTwoFactorViewController.h"
#import "DCLoginManager.h"

@interface DCTwoFactorViewController ()

@property (strong, nonatomic) UIActivityIndicatorView *spinner;

@end

@implementation DCTwoFactorViewController

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


- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.buttonVerify.enabled = NO;
    
    [self.navBar setBackgroundImage:[UIImage imageNamed:@"TbarBG"]
                     forBarMetrics:UIBarMetricsDefault];
    
    // Skin the verify button
    [self.buttonVerify setBackgroundImage:[UIImage imageNamed:@"BarButtonDone"]
                                forState:UIControlStateNormal
                              barMetrics:UIBarMetricsDefault];
    [self.buttonVerify setBackgroundImage:[UIImage imageNamed:@"BarButtonDonePressed"]
                                forState:UIControlStateHighlighted
                              barMetrics:UIBarMetricsDefault];
    
    // Skin the cancel button
    [self.buttonCancel setBackgroundImage:[UIImage imageNamed:@"BarButton"]
                                 forState:UIControlStateNormal
                               barMetrics:UIBarMetricsDefault];
    [self.buttonCancel setBackgroundImage:[UIImage imageNamed:@"BarButtonPressed"]
                                 forState:UIControlStateHighlighted
                               barMetrics:UIBarMetricsDefault];
    
    UIView *spinnerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 56, 30)];
    
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
    
    // Spinner for user feedback
    self.spinner = [[UIActivityIndicatorView alloc]
                    initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.center = CGPointMake(spinnerContainer.bounds.size.width / 2,
                                      spinnerContainer.bounds.size.height / 2);
    [spinnerContainer addSubview:self.spinner];
    self.spinnerItem = [[UIBarButtonItem alloc] initWithCustomView:spinnerContainer];
    
    self.fieldCode.delegate = self;
    
    
    // Code Field Styling
    UIImage *fieldImg = [UIImage imageNamed:@"MessageField"];
    UIEdgeInsets caps  = UIEdgeInsetsMake(15, 15, 15, 15);
    
    UIImage *stretchedField;
    if ([fieldImg respondsToSelector:@selector(resizableImageWithCapInsets:resizingMode:)]) {
        stretchedField = [fieldImg resizableImageWithCapInsets:caps
                                                  resizingMode:UIImageResizingModeStretch];
    } else {
        stretchedField = [fieldImg stretchableImageWithLeftCapWidth:15 topCapHeight:15];
    }
    
    self.fieldCode.background    = stretchedField;
    
    [self.fieldCode becomeFirstResponder];
}

#pragma mark - Loading state

- (void)setLoading:(BOOL)loading {
    self.buttonVerify.enabled = !loading;
    if (loading) {
        [self.spinner startAnimating];
        self.navigationItem.rightBarButtonItem = self.spinnerItem;
    } else {
        [self.spinner stopAnimating];
        self.navigationItem.rightBarButtonItem = self.buttonVerify;
    }
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self didTapVerify];
    return YES;
}

- (BOOL)textField:(UITextField *)textField
shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string {
    NSString *newText = [textField.text stringByReplacingCharactersInRange:range
                                                                withString:string];

    if (newText.length == 6) {
        self.buttonVerify.enabled = YES;
    } else {
        self.buttonVerify.enabled = NO;
    }
    return newText.length <= 6;
}

#pragma mark - Actions

- (IBAction)didTapVerify {
    NSString *code = [self.fieldCode.text
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    self.labelWarning.hidden = YES;
    [self setLoading:YES];
    
    [DCLoginManager loginTwoFactorWithCode:code
                                    ticket:self.twoFactorTicket
                               fingerprint:self.twoFactorFingerprint
                                instanceID:self.twoFactorInstanceID
                                completion:^(NSString *token, NSError *error) {
                                    [self setLoading:NO];
                                    
                                    if (token) {
                                        [self dismissViewControllerAnimated:YES completion:^{
                                            if (self.completionBlock) {
                                                self.completionBlock(token);
                                            }
                                        }];
                                        return;
                                    }
                                    
                                    NSString *message = error.userInfo[DCLoginErrorServerMessageKey]
                                    ?: @"Invalid code. Please try again.";
                                    self.labelWarning.text   = message;
                                    self.labelWarning.hidden = NO;
                                    self.fieldCode.text      = @"";
                                }];
    NSLog(@"[2FA] Sending code: '%@' with ticket: '%@'", code, self.twoFactorTicket);
}

- (IBAction)didTapCancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end