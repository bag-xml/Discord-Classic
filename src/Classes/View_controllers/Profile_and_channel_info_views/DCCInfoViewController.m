//
//  DCCInfoViewController.m
//  Discord Classic
//
//  Created by XML on 12/11/23.
//  Copyright (c) 2023 bag.xml. All rights reserved.
//

#import "DCCInfoViewController.h"
#include <Foundation/Foundation.h>

@interface DCCInfoViewController ()

@end

@implementation DCCInfoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.recipients = [NSMutableArray array];
#warning TODO: fix member list not loading
    if (DCServerCommunicator.sharedInstance.selectedChannel && DCServerCommunicator.sharedInstance.selectedChannel.parentGuild) {
        NSLog(@"Selected guild: %@", [DCServerCommunicator.sharedInstance.selectedChannel.parentGuild name]);
        NSArray *members = [[DCServerCommunicator.sharedInstance.selectedChannel.parentGuild members] copy];
        for (DCUser *member in members) {
            [self.recipients addObject:member];
        }
    } else if (DCServerCommunicator.sharedInstance.selectedChannel) {
        NSLog(@"Selected channel: %@", DCServerCommunicator.sharedInstance.selectedChannel.name);
        NSArray *recipientDictionaries = (NSArray *)[DCServerCommunicator.sharedInstance.selectedChannel recipients];
        for (NSDictionary *recipient in recipientDictionaries) {
            DCUser *dcUser = [DCTools convertJsonUser:recipient cache:YES];
            [self.recipients addObject:dcUser];
        }
    } else {
        NSLog(@"No channel or guild selected!");
    }
}

- (NSInteger)tableView:(UITableView *)tableView
    numberOfRowsInSection:(NSInteger)section {
    return
        [DCServerCommunicator.sharedInstance.selectedChannel.recipients count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"hackyMode"]) {
        DCRecipientTableCell *cell =
            [tableView dequeueReusableCellWithIdentifier:@"Members cell"];
        DCUser *user                     = self.recipients[indexPath.row];
        cell.userName.text               = user.globalName;
        cell.userPFP.image               = user.profileImage;
        cell.userPFP.layer.cornerRadius  = cell.userPFP.frame.size.width / 2.0;
        cell.userPFP.layer.masksToBounds = YES;
        return cell;
    } else {
        UITableViewCell *cell =
            [tableView dequeueReusableCellWithIdentifier:@"Members Cell"];
        if (!cell) {
            cell = UITableViewCell.new;
        }
        DCUser *user        = self.recipients[indexPath.row];
        cell.textLabel.text = user.username;
        return cell;
    }
}


- (void)tableView:(UITableView *)tableView
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    self.selectedUser = self.recipients[indexPath.row];
    [self performSegueWithIdentifier:@"channelinfo to contact" sender:self];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
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
