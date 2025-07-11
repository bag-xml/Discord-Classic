//
//  DCGuildViewController.m
//  Discord Classic
//
//  Created by bag.xml on 3/4/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import "DCGuildListViewController.h"
#import "DCChannelListViewController.h"
#import "DCGuild.h"
#import "DCServerCommunicator.h"
#import "DCTools.h"

@implementation DCGuildListViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Go to settings if no token is set
    if (!DCServerCommunicator.sharedInstance.token.length) {
        [self performSegueWithIdentifier:@"to Settings" sender:self];
    }

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleReady)
                                               name:@"READY"
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleReady)
                                               name:@"MESSAGE ACK"
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleReady)
                                               name:@"RELOAD GUILD LIST"
                                             object:nil];
}


- (void)handleReady {
    // Refresh tableView data on READY notification
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}


- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell =
        [tableView dequeueReusableCellWithIdentifier:@"Guild Cell"];

    DCGuild *guildAtRowIndex = [DCServerCommunicator.sharedInstance.guilds
        objectAtIndex:indexPath.row];

    // Show blue indicator if guild has any unread messages
    if (guildAtRowIndex.unread) {
        [cell setAccessoryType:UITableViewCellAccessoryDetailDisclosureButton];
    } else {
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
    }

    // Guild name and icon
    [cell.textLabel setText:guildAtRowIndex.name];
    [cell.imageView setImage:guildAtRowIndex.icon];

    return cell;
}


- (void)tableView:(UITableView *)tableView
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([DCServerCommunicator.sharedInstance.guilds objectAtIndex:indexPath.row]
        != DCServerCommunicator.sharedInstance.selectedGuild) {
        // Clear the loaded users array for lazy memory management. This will be
        // fleshed out more later
        DCServerCommunicator.sharedInstance.loadedUsers =
            NSMutableDictionary.new;
        // Assign the selected guild
        DCServerCommunicator.sharedInstance.selectedGuild =
            [DCServerCommunicator.sharedInstance.guilds
                objectAtIndex:indexPath.row];
    }

    // Transition to channel list
    [self performSegueWithIdentifier:@"Guilds to Channels" sender:self];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"Guilds to Channels"]) {
        DCChannelListViewController *channelListViewController =
            [segue destinationViewController];

        if ([channelListViewController
                isKindOfClass:DCChannelListViewController.class]) {
            // Assign selected guild for the channel list we are transitioning
            // to.
            channelListViewController.selectedGuild =
                DCServerCommunicator.sharedInstance.selectedGuild;
        }
    }
}

- (IBAction)joinGuildPrompt:(id)sender {
    UIAlertView *joinPrompt =
        [[UIAlertView alloc] initWithTitle:@"Enter invite code"
                                   message:nil
                                  delegate:self
                         cancelButtonTitle:@"Cancel"
                         otherButtonTitles:@"Join", nil];

    [joinPrompt setAlertViewStyle:UIAlertViewStylePlainTextInput];
    [joinPrompt setDelegate:self];
    [joinPrompt show];
}

- (void)alertView:(UIAlertView *)alertView
    clickedButtonAtIndex:(NSInteger)buttonIndex {
    if ([[alertView buttonTitleAtIndex:buttonIndex] isEqualToString:@"Join"]) {
        [DCTools joinGuild:[alertView textFieldAtIndex:0].text];
    }
}

- (void)reconnect {
    [DCServerCommunicator.sharedInstance reconnect];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView
    numberOfRowsInSection:(NSInteger)section {
    return DCServerCommunicator.sharedInstance.guilds.count;
}


@end