//
//  DCCInfoViewController.m
//  Discord Classic
//
//  Created by XML on 12/11/23.
//  Copyright (c) 2023 bag.xml. All rights reserved.
//

#import "DCCInfoViewController.h"
#include "DCUser.h"
#include "DCServerCommunicator.h"
#include <CoreGraphics/CGGeometry.h>
#include "DCMenuViewController.h"
#include "DCTools.h"
#include "DCRecipientTableCell.h"
#include "DCRole.h"
#include <Foundation/Foundation.h>
#import "DCContentManager.h"

@interface DCCInfoViewController ()

@end

@implementation DCCInfoViewController

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
    self.tableView.dataSource            = self;
    self.tableView.delegate              = self;

    [NSNotificationCenter.defaultCenter
            addObserver:self
               selector:@selector(guildMemberListUpdated:)
                   name:@"GuildMemberListUpdated"
                 object:nil];
    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(handleReloadUser:)
               name:@"RELOAD USER DATA"
             object:nil];

    if (DCServerCommunicator.sharedInstance.selectedChannel && [DCServerCommunicator.sharedInstance.selectedChannel.parentGuild.snowflake length] > 0) {
        // If a guild is selected, get the members from the guild
        self.title = [DCServerCommunicator.sharedInstance.selectedChannel.parentGuild name];
        self.navigationItem.title = self.title;
        DBGLOG(
            @"Selected channel: #%@ in guild: %@", 
            [DCServerCommunicator.sharedInstance.selectedChannel name], 
            [DCServerCommunicator.sharedInstance.selectedChannel.parentGuild name]
        );
        self.recipients = 
            [DCServerCommunicator.sharedInstance.selectedChannel.parentGuild.members mutableCopy];
    } else if (DCServerCommunicator.sharedInstance.selectedChannel) {
        DBGLOG(@"Selected channel: %@", DCServerCommunicator.sharedInstance.selectedChannel.name);
        self.recipients = 
            [DCServerCommunicator.sharedInstance.selectedChannel.recipients mutableCopy];
    } else {
        DBGLOG(@"No channel or guild selected!");
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [NSNotificationCenter.defaultCenter removeObserver:self name:@"RELOAD USER DATA" object:nil];
}

- (void)guildMemberListUpdated:(NSNotification *)notification {
    // Update the recipients list when the guild member list is updated
    if (!DCServerCommunicator.sharedInstance.selectedChannel) {
        return;
    }
    if ([DCServerCommunicator.sharedInstance.selectedChannel.parentGuild.snowflake length] <= 0) {
        self.recipients = [DCServerCommunicator.sharedInstance.selectedChannel.recipients mutableCopy];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
        });
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        self.recipients = [DCServerCommunicator.sharedInstance.selectedChannel.parentGuild.members mutableCopy];
        [self.tableView reloadData];
    });
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView
    numberOfRowsInSection:(NSInteger)section {
    if (DCServerCommunicator.sharedInstance.selectedChannel) {
        return [self.recipients count];
    } else {
        DBGLOG(@"No rows for nothing...");
        return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"hackyMode"]) {
        id item                              = self.recipients[indexPath.row];
        DCRecipientTableCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Members cell"];
        if (!cell) {
            NSCAssert(NO, @"Failed to dequeue DCRecipientTableCell");
            abort();
        }
        if ([item isKindOfClass:[DCUser class]]) {
            DCUser *user = item;
            cell.userName.text               = [user displayNameInGuild:DCServerCommunicator.sharedInstance.selectedChannel.parentGuild];
            if (user.profileImage && user.profileImage.size.width > 0) {
                cell.userPFP.image = user.profileImage;
            } else {
                cell.userPFP.image = nil;
                [DCTools getUserAvatar:user];
            }
            if ([DCServerCommunicator.sharedInstance.selectedChannel.parentGuild.snowflake length] > 0) {
                cell.statusLight.hidden = NO;
                cell.statusLight.image  = [UIImage imageNamed:[DCMenuViewController imageNameForStatus:user.status]];
            } else {
                cell.statusLight.hidden = YES;
            }
        } else if ([item isKindOfClass:[DCRole class]]) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Roles Cell"];
            if (cell == nil) {
               cell = [[UITableViewCell alloc]
                     initWithStyle:UITableViewCellStyleDefault
                   reuseIdentifier:@"Roles Cell"];
               // make unclickable
               [cell setSelectionStyle:UITableViewCellSelectionStyleNone];
               [cell setUserInteractionEnabled:NO];
               [cell.textLabel setEnabled:NO];
               [cell.textLabel setFont:[UIFont fontWithName:@"HelveticaNeue" size:15.0]];
               [cell.detailTextLabel setEnabled:NO];
               [cell setAlpha:0.5];
               [cell setAccessoryType:UITableViewCellAccessoryNone];
            }
            DCRole *role = item;
            [cell.textLabel setText:role.name];
            return cell;
        } else {
            DBGLOG(@"Unknown item type in recipients: %@", [item class]);
            cell.textLabel.text = @"Unknown";
            cell.imageView.image = nil;
            cell.detailTextLabel.text = nil;
            cell.textLabel.text = @"Unknown";
        }
        return cell;
    } else {
        UITableViewCell *cell =
            [tableView dequeueReusableCellWithIdentifier:@"Members Cell"];
        if (!cell) {
            cell = UITableViewCell.new;
        }
        id item        = self.recipients[indexPath.row];
        if ([item isKindOfClass:[DCUser class]]) {
            DCUser *user = (DCUser *)item;
            cell.textLabel.text = user.username;
        } else if ([item isKindOfClass:[DCRole class]]) {
            DCRole *role = (DCRole *)item;
            cell.textLabel.text = role.name;
        } else {
            cell.textLabel.text = @"Unknown";
        }
        return cell;
    }
}

- (CGFloat)tableView:(UITableView *)tableView
    heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == self.tableView) {
        id item = self.recipients[indexPath.row];
        if ([item isKindOfClass:[DCRole class]]) {
            return 20.0;
        }
    }
    return tableView.rowHeight;
}

- (void)tableView:(UITableView *)tableView
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    self.selectedUser = self.recipients[indexPath.row];
    [self performSegueWithIdentifier:@"channelinfo to contact" sender:self];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)handleReloadUser:(NSNotification *)notification {
    DCUser *user = notification.object;
    if (!user) return;
    NSUInteger index = [self.recipients indexOfObject:user];
    if (index == NSNotFound) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        // Guard against stale index after async dispatch
        if (index >= [self.tableView numberOfRowsInSection:0]) return;
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
        [self.tableView beginUpdates];
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        [self.tableView endUpdates];
    });
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
