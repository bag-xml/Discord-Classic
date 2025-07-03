//
//  DCMutualFriendsViewController.m
//  Discord Classic
//
//  Created by XML on 04/01/25.
//  Copyright (c) 2025 bag.xml. All rights reserved.
//

#import "DCMutualFriendsViewController.h"
#include <UIKit/UIKit.h>

@interface DCMutualFriendsViewController ()

@end

@implementation DCMutualFriendsViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self.titleBar setBackgroundImage:[UIImage imageNamed:@"TbarBG"]
                        forBarMetrics:UIBarMetricsDefault];
    [self.doneButton setBackgroundImage:[UIImage imageNamed:@"BarButton"]
                               forState:UIControlStateNormal
                             barMetrics:UIBarMetricsDefault];
    [self.doneButton setBackgroundImage:[UIImage imageNamed:@"BarButtonPressed"]
                               forState:UIControlStateHighlighted
                             barMetrics:UIBarMetricsDefault];

    // fix last element in table view being cut off
    UIEdgeInsets insets                     = self.mutTableView.contentInset;
    insets.bottom                           = 44;
    self.mutTableView.contentInset          = insets;
    self.mutTableView.scrollIndicatorInsets = insets;

    self.mutTableView.delegate   = self;
    self.mutTableView.dataSource = self;
    self.recipients              = [NSMutableArray array];

#warning TODO: fix cast
    NSArray *recipientDictionaries = (NSArray *)self.mutualFriendsList;
    for (NSDictionary *recipient in recipientDictionaries) {
        DCUser *dcUser = [DCTools convertJsonUser:recipient cache:YES];
        [self.recipients addObject:dcUser];
    }
}

- (NSInteger)tableView:(UITableView *)tableView
    numberOfRowsInSection:(NSInteger)section {
    return self.mutualFriendsList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DCRecipientTableCell *cell =
        [tableView dequeueReusableCellWithIdentifier:@"Members cell"];
    DCUser *user                     = self.recipients[indexPath.row];
    cell.userName.text               = user.globalName;
    cell.userPFP.image               = user.profileImage;
    cell.userPFP.layer.cornerRadius  = cell.userPFP.frame.size.width / 2.0;
    cell.userPFP.layer.masksToBounds = YES;
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView
    heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 52;
}

- (void)tableView:(UITableView *)tableView
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    self.selectedUser = self.recipients[indexPath.row];
    [self performSegueWithIdentifier:@"mutual to contact" sender:self];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}
- (IBAction)dismiss:(id)sender {
    [self dismissModalViewControllerAnimated:YES];
}


- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.destinationViewController
            isKindOfClass:[DCContactViewController class]]) {
        DCContactViewController *contactVC =
            (DCContactViewController *)segue.destinationViewController;
        contactVC.selectedUser = self.selectedUser;
    }
}


@end
