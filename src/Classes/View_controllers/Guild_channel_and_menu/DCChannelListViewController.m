//
//  DCChannelViewController.m
//  Discord Classic
//
//  Created by bag.xml on 3/5/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import "DCChannelListViewController.h"
#import "DCCInfoViewController.h"
#import "DCChannel.h"
#import "DCChatViewController.h"
#import "DCGuild.h"
#import "DCServerCommunicator.h"
#import "TRMalleableFrameView.h"

@interface DCChannelListViewController ()
@property int selectedChannelIndex;
@property DCChannel *selectedChannel;
@end

@implementation DCChannelListViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleMessageAck)
                                               name:@"MESSAGE ACK"
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleMessageAck)
                                               name:@"RELOAD CHANNEL LIST"
                                             object:nil];
}


- (void)viewWillAppear:(BOOL)animated {
    [self.navigationItem setTitle:self.selectedGuild.name];
    //[self.tableView reloadData];
    [DCServerCommunicator.sharedInstance setSelectedChannel:nil];

    // nono we wouldnt want rebels getting BASIC FEATURES!111111 :devious:
    /*if ([self.navigationItem.title isEqualToString:@"Direct Messages"]) { n
        // Sort the DMs list by most recent...
        NSSortDescriptor *sortDescriptor = [NSSortDescriptor
    sortDescriptorWithKey:@"lastMessageId" ascending:NO
    selector:@selector(localizedStandardCompare:)]; [self.selectedGuild.channels
    sortUsingDescriptors:@[sortDescriptor]]; [self.tableView reloadData];
    }*/
}


- (void)handleMessageAck {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}


- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Show blue indicator if channel contains any unread messages
    DCChannel *channelAtRowIndex =
        [self.selectedGuild.channels objectAtIndex:indexPath.row];

    if (channelAtRowIndex.type == 4) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Category Cell"];
        if (cell == nil) {
            cell = [[UITableViewCell alloc]
                  initWithStyle:UITableViewCellStyleDefault
                reuseIdentifier:@"Category Cell"];
            // make unclickable
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.userInteractionEnabled = NO;
            cell.textLabel.enabled = NO;
            cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
            cell.detailTextLabel.enabled = NO;
            cell.alpha = 0.5;
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
        cell.textLabel.text = channelAtRowIndex.name;
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Channel Cell"];

    cell.accessoryType = channelAtRowIndex.unread
        ? UITableViewCellAccessoryDetailDisclosureButton
        : UITableViewCellAccessoryDisclosureIndicator;

    // Channel name
    cell.textLabel.text = channelAtRowIndex.name;

    return cell;
}

- (void)tableView:(UITableView *)tableView
      willDisplayCell:(UITableViewCell *)cell
    forRowAtIndexPath:(NSIndexPath *)indexPath {
    // make guild icons a fixed size
    cell.imageView.frame               = CGRectMake(0, 0, 32, 32);
    cell.imageView.layer.cornerRadius  = cell.imageView.frame.size.height / 2.0;
    cell.imageView.layer.masksToBounds = YES;
    [cell.imageView setNeedsDisplay];
    [cell layoutIfNeeded];
}


- (void)tableView:(UITableView *)tableView
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    DCServerCommunicator.sharedInstance.selectedChannel =
        [self.selectedGuild.channels objectAtIndex:indexPath.row];
    
    if (DCServerCommunicator.sharedInstance.selectedChannel.type == 4) {
        // If the channel is a category, do nothing
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }

    // Mark channel messages as read and refresh the channel object accordingly
    [DCServerCommunicator.sharedInstance.selectedChannel
        ackMessage:DCServerCommunicator.sharedInstance.selectedChannel
                       .lastMessageId];
    [DCServerCommunicator.sharedInstance.selectedChannel checkIfRead];

    // Remove the blue indicator since the channel has been read
    [[self.tableView cellForRowAtIndexPath:indexPath]
        setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];

    // Transition to chat view
    [self performSegueWithIdentifier:@"Channels to Chat" sender:self];
}


- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"Channels to Chat"]) {
        DCChatViewController *chatViewController =
            [segue destinationViewController];

        if ([chatViewController isKindOfClass:[DCChatViewController class]]) {
            // Initialize messages
            [NSNotificationCenter.defaultCenter
                postNotificationName:@"NUKE CHAT DATA"
                              object:nil];

            // Add a '#' if appropriate to the channel name in the navigation bar
            NSString *formattedChannelName;
            if (DCServerCommunicator.sharedInstance.selectedChannel.type == 0) {
                formattedChannelName = [@"#"
                    stringByAppendingString:DCServerCommunicator.sharedInstance
                                                .selectedChannel.name];
            } else {
                formattedChannelName = DCServerCommunicator.sharedInstance.selectedChannel.name;
            }
            chatViewController.navigationItem.title = formattedChannelName;

            // Populate the message view with the last 50 messages
            [chatViewController getMessages:50 beforeMessage:nil];

            // Chat view is watching the present conversation (auto scroll with
            // new messages)
            [chatViewController setViewingPresentTime:true];
        }
    } else if ([segue.identifier isEqualToString:@"Channels to RightSidebar"]) {
        DCCInfoViewController *rightSidebar = [segue destinationViewController];

        if ([rightSidebar isKindOfClass:[DCChatViewController class]]) {
            rightSidebar.navigationItem.title = self.selectedGuild.name;
        }
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}
- (NSInteger)tableView:(UITableView *)tableView
    numberOfRowsInSection:(NSInteger)section {
    return self.selectedGuild.channels.count;
}
@end
