//
//  DCTokenLoginPage.m
//  Discord Classic
//
//  Created by Ayeris on 2/28/26.
//  Copyright (c) 2026 bag.xml. All rights reserved.
//

#import "DCTokenLoginPage.h"
#import "DCIntroductionPage.h"

@interface DCTokenLoginPage ()
@property (strong, nonatomic) UIActivityIndicatorView *spinner;
@end

@implementation DCTokenLoginPage

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

    self.buttonLogIn.enabled = NO;
    
    [self.navBar setBackgroundImage:[UIImage imageNamed:@"TbarBG"]
                      forBarMetrics:UIBarMetricsDefault];
    
    // Skin the verify button
    [self.buttonLogIn setBackgroundImage:[UIImage imageNamed:@"BarButtonDone"]
                                 forState:UIControlStateNormal
                               barMetrics:UIBarMetricsDefault];
    [self.buttonLogIn setBackgroundImage:[UIImage imageNamed:@"BarButtonDonePressed"]
                                 forState:UIControlStateHighlighted
                               barMetrics:UIBarMetricsDefault];
    
    // Skin the cancel button
    [self.buttonCancel setBackgroundImage:[UIImage imageNamed:@"BarButton"]
                                 forState:UIControlStateNormal
                               barMetrics:UIBarMetricsDefault];
    [self.buttonCancel setBackgroundImage:[UIImage imageNamed:@"BarButtonPressed"]
                                 forState:UIControlStateHighlighted
                               barMetrics:UIBarMetricsDefault];
    
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
    
    // Spinner for user feedback
    self.spinner = [[UIActivityIndicatorView alloc]
                    initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.center = CGPointMake(spinnerContainer.bounds.size.width / 2,
                                      spinnerContainer.bounds.size.height / 2);
    [spinnerContainer addSubview:self.spinner];
    self.spinnerItem = [[UIBarButtonItem alloc] initWithCustomView:spinnerContainer];
    
    self.fieldToken.delegate = self;
    
    
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
    
    self.fieldToken.background    = stretchedField;
    
    [self.fieldToken becomeFirstResponder];
}

#pragma mark - Loading state

- (void)setLoading:(BOOL)loading {
    self.buttonLogIn.enabled = !loading;
    if (loading) {
        [self.spinner startAnimating];
        self.navigationItem.rightBarButtonItem = self.spinnerItem;
    } else {
        [self.spinner stopAnimating];
        self.navigationItem.rightBarButtonItem = self.buttonLogIn;
    }
}


#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self didTapLogIn];
    return YES;
}

- (BOOL)textField:(UITextField *)textField
shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string {
    NSString *newText = [textField.text stringByReplacingCharactersInRange:range
                                                                withString:string];

    if (newText.length == 70) {
        self.buttonLogIn.enabled = YES;
    } else {
        self.buttonLogIn.enabled = NO;
    }
    return newText.length <= 70;
}

#pragma mark - Actions

- (IBAction)didTapLogIn {
    NSString *token = [self.fieldToken.text
                       stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    [NSUserDefaults.standardUserDefaults setObject:token forKey:@"token"];
    [NSUserDefaults.standardUserDefaults synchronize];
    DCServerCommunicator.sharedInstance.token = token;
    [DCServerCommunicator.sharedInstance reconnect];
    
    [self dismissViewControllerAnimated:YES completion:^{
        [self.introPage didLogin];
    }];
}

- (IBAction)didTapCancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
