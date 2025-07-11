//
//  DCMenuViewController.m
//  Discord Classic
//
//  Created by bag.xml on 27/01/24.
//  Copyright (c) 2024 bag.xml. All rights reserved.
//

#import "DCMenuViewController.h"
#include <dispatch/dispatch.h>
#include <Foundation/Foundation.h>
#include <objc/NSObjCRuntime.h>
#include "DCGuild.h"
#include "DCServerCommunicator.h"

@interface DCMenuViewController ()
@end

@implementation DCMenuViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Go to settings if no token is set
    if (!DCServerCommunicator.sharedInstance.token.length) {
        [self performSegueWithIdentifier:@"to Tokenpage" sender:self];
    }

    // NOTIF OBSERVERS
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleReady)
                                               name:@"READY"
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleMessageAck)
                                               name:@"MESSAGE ACK"
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleMessageAck)
                                               name:@"RELOAD CHANNEL LIST"
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleReady)
                                               name:@"RELOAD GUILD LIST"
                                             object:nil];
                                             
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(handleNotificationTap:)
               name:@"NavigateToChannel"
             object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(exitedChatController)
               name:@"ChannelSelectionCleared"
             object:nil];
    // NOTIF OBSERVERS END
    [self.navigationController.navigationBar
        setBackgroundImage:[UIImage imageNamed:@"TbarBG"]
             forBarMetrics:UIBarMetricsDefault];

    self.experimentalMode =
        [[NSUserDefaults standardUserDefaults] boolForKey:@"experimentalMode"];
    self.totalView.hidden = YES;
}


// block that handles what the app does if you open it via a push ntoification

- (void)handleNotificationTap:(NSNotification *)notification {
    NSString *channelId = notification.userInfo[@"channelId"];
    if (channelId) {
        // NSLog(@"Navigating to channel with ID: %@", channelId);
        [self navigateToChannelWithId:channelId];
    }
}

- (void)exitedChatController {
    // NSLog(@"EXITING CHAT VIEW");
    self.selectedChannel = nil;
}

- (void)navigateToChannelWithId:(NSString *)channelId {
    for (DCGuild *guild in DCServerCommunicator.sharedInstance.guilds) {
        for (DCChannel *channel in guild.channels) {
            if ([channel.snowflake isEqualToString:channelId]) {
                // NSLog(@"channel id: %@", channelId);
                if (self.selectedChannel &&
                    [self.selectedChannel.snowflake
                        isEqualToString:channelId]) {
                    // NSLog(@"ok");
                    return;
                }
                self.selectedGuild                                  = guild;
                self.selectedChannel                                = channel;
                DCServerCommunicator.sharedInstance.selectedChannel = channel;

                dispatch_async(dispatch_get_main_queue(), ^{
                    [self performSegueWithIdentifier:@"guilds to chat"
                                              sender:self];
                });
                return;
            }
        }
    }
}
// end of block

// reload
/*- (void)handleReady {
    [self.guildTableView reloadData];
    [self.channelTableView reloadData];
}*/


- (void)handleReady {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.guildTableView reloadData];
        [self.channelTableView reloadData];

        if (!self.refreshControl) {
            self.refreshControl = UIRefreshControl.new;

            self.refreshControl.attributedTitle =
                [[NSAttributedString alloc] initWithString:@"Reload"];

            [self.guildTableView addSubview:self.refreshControl];

            [self.refreshControl addTarget:self
                                    action:@selector(reconnect)
                          forControlEvents:UIControlEventValueChanged];
        }
    });
}

- (void)reloadTable {
    [self handleMessageAck];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.channelTableView reloadData];
        [self.reloadControl endRefreshing];
    });
}

- (void)reconnect {
    [DCServerCommunicator.sharedInstance reconnect];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.refreshControl endRefreshing];
    });
}

// reload end
// misc
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (void)handleMessageAck {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.channelTableView reloadData];
    });
}

// idk what to do with this ngl
- (void)viewWillAppear:(BOOL)animated {
    if (self.selectedGuild) {
        // NSLog(@"clear selected channel!");
        // [DCServerCommunicator.sharedInstance setSelectedChannel:nil];
        if ([self.navigationItem.title isEqualToString:@"Direct Messages"]) {
            NSSortDescriptor *sortDescriptor = [NSSortDescriptor
                sortDescriptorWithKey:@"lastMessageId"
                            ascending:NO
                             selector:@selector(localizedStandardCompare:)];
            [self.selectedGuild.channels
                sortUsingDescriptors:@[ sortDescriptor ]];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.channelTableView reloadData];
        });
    } else {
        [self.navigationItem setTitle:@"Discord"];
    }
}

// misc end
- (IBAction)moreInfo:(id)sender {
    UIActionSheet *messageActionSheet =
        [[UIActionSheet alloc] initWithTitle:self.selectedGuild.name
                                    delegate:self
                           cancelButtonTitle:@"Okay"
                      destructiveButtonTitle:nil
                           otherButtonTitles:nil, nil];
    [messageActionSheet setDelegate:self];
    [messageActionSheet showInView:self.view.superview];
}

- (IBAction)userInfo:(id)sender {
    [self performSegueWithIdentifier:@"guilds to own info" sender:self];
}

- (void)tableView:(UITableView *)tableView
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == self.guildTableView) {
        self.selectedGuild = [DCServerCommunicator.sharedInstance.guilds
            objectAtIndex:indexPath.row];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        if (self.selectedGuild.banner == nil) {
            self.guildBanner.image = [UIImage imageNamed:@"No-Header"];
        } else {
            self.guildBanner.image = self.selectedGuild.banner;
        }
        [self.navigationItem setTitle:self.selectedGuild.name];
        self.guildLabel.text = self.selectedGuild.name;
        [self.channelTableView reloadData];
        if (self.guildLabel &&
            [self.guildLabel.text isEqualToString:@"Direct Messages"]) {
            self.totalView.hidden = NO;
            self.userName.text =
                [[DCServerCommunicator.sharedInstance currentUserInfo]
                    objectForKey:@"global_name"];
            self.globalName.text       = [NSString
                stringWithFormat:@"@%@",
                                 [[DCServerCommunicator
                                         .sharedInstance currentUserInfo]
                                     objectForKey:@"username"]];
            self.guildTotalView.hidden = YES;
        } else {
            self.totalView.hidden      = YES;
            self.guildTotalView.hidden = NO;
        }
    } else if (tableView == self.channelTableView) {
        if (!self.selectedGuild || !self.selectedGuild.channels || self.selectedGuild.channels.count <= indexPath.row) {
#ifdef DEBUG
            NSLog(@"Selected guild or channels are not set or index out of bounds");
#endif
            return;
        }

        DCChannel *channelAtRowIndex =
            [self.selectedGuild.channels objectAtIndex:indexPath.row];

        // If the channel is a category, do nothing
        if (channelAtRowIndex.type == 4) {
            [tableView deselectRowAtIndexPath:indexPath animated:YES];
            return;
        }

        DCServerCommunicator.sharedInstance.selectedChannel = channelAtRowIndex;
        self.selectedChannel                                = channelAtRowIndex;

        [DCServerCommunicator.sharedInstance
        sendGuildSubscriptionWithGuildId:self.selectedGuild.snowflake
                               channelId:self.selectedChannel.snowflake];

        // Mark channel messages as read and refresh the channel object
        // accordingly
        [DCServerCommunicator.sharedInstance.selectedChannel
            ackMessage:DCServerCommunicator.sharedInstance.selectedChannel
                           .lastMessageId];
        [DCServerCommunicator.sharedInstance.selectedChannel checkIfRead];

        // Remove the blue indicator since the channel has been read
        //[[self.channelTableView cellForRowAtIndexPath:indexPath]
        // setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];

        if (self.experimentalMode) {
            UINavigationController *navigationController =
                (UINavigationController *)
                    self.slideMenuController.contentViewController;
            DCChatViewController *contentViewController =
                navigationController.viewControllers.firstObject;
            if ([contentViewController
                    isKindOfClass:[DCChatViewController class]]) {
                [NSNotificationCenter.defaultCenter
                postNotificationName:@"NUKE CHAT DATA"
                              object:nil];
                [NSNotificationCenter.defaultCenter postNotificationName:@"GuildMemberListUpdated" object:nil];
                NSString *formattedChannelName;
                if (DCServerCommunicator.sharedInstance.selectedChannel.type
                    == 0) {
                    formattedChannelName = [@"#"
                        stringByAppendingString:DCServerCommunicator
                                                    .sharedInstance
                                                    .selectedChannel.name];
                } else {
                    formattedChannelName = DCServerCommunicator.sharedInstance
                                               .selectedChannel.name;
                }
                [contentViewController.navigationItem
                    setTitle:formattedChannelName];
                [contentViewController getMessages:50 beforeMessage:nil];
                [contentViewController setViewingPresentTime:true];
                [self.slideMenuController hideMenu:YES];
            }
        } else {
            [self performSegueWithIdentifier:@"guilds to chat" sender:self];
        }
        //[tableView cellForRowAtIndexPath:indexPath].accessoryType =
        // UITableViewCellAccessoryDisclosureIndicator;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == self.channelTableView) {
        DCChannel *channelAtRowIndex =
            [self.selectedGuild.channels objectAtIndex:indexPath.row];
        if (channelAtRowIndex.type == 4) {
            // Category cell height
            return 20.0;
        }
    }
    return tableView.rowHeight;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == self.guildTableView) {
        // Use the DCGuildTableViewCell
        DCGuildTableViewCell *cell =
            [tableView dequeueReusableCellWithIdentifier:@"guild"];
        if (cell == nil) {
            cell = [[DCGuildTableViewCell alloc]
                  initWithStyle:UITableViewCellStyleDefault
                reuseIdentifier:@"guild"];
        }


        // Sorting guilds based on userInfo[@"guildPositions"] array
        if (!DCServerCommunicator.sharedInstance.guildsIsSorted) {
            NSUInteger guildCount        = [DCServerCommunicator.sharedInstance.guilds count];
            NSMutableArray *sortedGuilds = [NSMutableArray arrayWithCapacity:guildCount];
            NSNull *nullObject           = [NSNull null];
            // init to be able to index
            for (NSUInteger i = 0; i < guildCount; i++) {
                [sortedGuilds addObject:nullObject];
            }
            for (DCGuild *guild in DCServerCommunicator.sharedInstance.guilds) {
                int index = [DCServerCommunicator.sharedInstance.currentUserInfo[@"guildPositions"] indexOfObject:guild.snowflake];
                if (index != NSNotFound) {
                    sortedGuilds[index + 1] = guild;
                } else {
                    if ([sortedGuilds[0] isEqual:nullObject]) {
                        // If the first element is still null, must be private guild
                        sortedGuilds[0] = guild;
                    } else {
                        // Otherwise, append to the end of the array
                        [sortedGuilds addObject:guild];
                    }
                }
            }
            [sortedGuilds removeObjectIdenticalTo:nullObject];
            DCServerCommunicator.sharedInstance.guilds = sortedGuilds;
            NSAssert(sortedGuilds && [sortedGuilds count] != 0, @"No sorted guilds found");
            DCServerCommunicator.sharedInstance.guildsIsSorted = YES;
        }

        NSCAssert(
            DCServerCommunicator.sharedInstance.guilds && DCServerCommunicator.sharedInstance.guilds.count > indexPath.row,
            @"Guilds array is empty or index out of bounds"
        );

        DCGuild *guildAtRowIndex = [DCServerCommunicator.sharedInstance.guilds
            objectAtIndex:indexPath.row];

        NSCAssert((NSNull *)guildAtRowIndex != [NSNull null], @"Guild at row index is NSNull");

        // Show blue indicator if guild has any unread messages
        cell.unreadMessages.hidden = !guildAtRowIndex.unread;

        // Guild name and icon
        [cell.guildAvatar setImage:guildAtRowIndex.icon];

        cell.guildAvatar.layer.cornerRadius =
            cell.guildAvatar.frame.size.width / 6.0;
        cell.guildAvatar.layer.masksToBounds = YES;

        return cell;
    }

    if (tableView == self.channelTableView) {
        if (self.guildLabel &&
            [self.guildLabel.text isEqualToString:@"Direct Messages"]) {
            DCPrivateChannelTableCell *cell =
                [tableView dequeueReusableCellWithIdentifier:@"private"];
            if (cell == nil) {
                cell = [[DCPrivateChannelTableCell alloc]
                      initWithStyle:UITableViewCellStyleDefault
                    reuseIdentifier:@"private"];
            }

            NSCAssert(
                self.selectedGuild && self.selectedGuild.channels && self.selectedGuild.channels.count > indexPath.row,
                @"Invalid guild, channel, or index"
            );

            DCChannel *channelAtRowIndex =
                [self.selectedGuild.channels objectAtIndex:indexPath.row];

            NSCAssert((NSNull *)channelAtRowIndex != [NSNull null], @"Channel at row index is NSNull");

            cell.unreadMessages.hidden = !channelAtRowIndex.unread;
            [cell.nameLabel setText:channelAtRowIndex.name];

            if (channelAtRowIndex.icon != nil &&
                [channelAtRowIndex.icon class] == [UIImage class]) {
                [cell.pfp setImage:channelAtRowIndex.icon];
                cell.pfp.layer.cornerRadius  = cell.pfp.frame.size.width / 2.0;
                cell.pfp.layer.masksToBounds = YES;
            }

            // Presence indicator logic for DM channels (type 1, one-on-one)
            if (channelAtRowIndex.type == 1
                && channelAtRowIndex.users.count == 2) {
                DCUser *buddy = nil;

                // Iterate over users to find the DM partner
                for (NSDictionary *userDict in channelAtRowIndex.users) {
                    NSString *userId = [userDict valueForKey:@"snowflake"];

                    // Exclude self from buddy selection
                    if (![userId
                            isEqualToString:DCServerCommunicator.sharedInstance
                                                .snowflake]) {
                        // Attempt to fetch from cache
                        buddy = [DCServerCommunicator.sharedInstance.loadedUsers
                            objectForKey:userId];

                        // If not in cache, construct user manually from
                        // dictionary
                        if (!buddy) {
                            buddy           = [[DCUser alloc] init];
                            buddy.snowflake = userId;
                            buddy.username  = [userDict valueForKey:@"username"];
                            buddy.status =
                                [userDict valueForKey:@"status"] ?: @"offline";
                        }
                        break;
                    }
                }

                // Update the status image based on the buddy's status
                if (buddy) {
                    NSString *statusImageName =
                        [self.class imageNameForStatus:buddy.status];
                    cell.statusImage.image =
                        [UIImage imageNamed:statusImageName];
                } else {
                    cell.statusImage.image = [UIImage imageNamed:@"offline"];
                }

                cell.statusImage.hidden = NO;
            } else {
                // Hide status indicator for non-DM or group channels
                cell.statusImage.hidden = YES;
            }

            return cell;

        } else {
            NSCAssert(self.selectedGuild && self.selectedGuild.channels && self.selectedGuild.channels.count > indexPath.row, @"Invalid guild, channel, or index");

            DCChannel *channelAtRowIndex =
                [self.selectedGuild.channels objectAtIndex:indexPath.row];

            NSCAssert((NSNull *)channelAtRowIndex != [NSNull null], @"Channel at row index is NSNull");

            if (channelAtRowIndex.type == 4) {
                UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Category Cell"];
                if (cell == nil) {
                    cell = [[UITableViewCell alloc]
                          initWithStyle:UITableViewCellStyleDefault
                        reuseIdentifier:@"Category Cell"];
                    // make unclickable
                    [cell setSelectionStyle:UITableViewCellSelectionStyleNone];
                    [cell setUserInteractionEnabled:NO];
                    [cell.textLabel setEnabled:NO];
                    [cell.textLabel setFont:[UIFont fontWithName:@"HelveticaNeue" size:15.0]];
                    [cell.detailTextLabel setEnabled:NO];
                    [cell setAlpha:0.5];
                    [cell setAccessoryType:UITableViewCellAccessoryNone];
                }
                [cell.textLabel setText:channelAtRowIndex.name];
                return cell;
            }

            DCChannelViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"channel"];
            if (cell == nil) {
                cell = [[DCChannelViewCell alloc]
                      initWithStyle:UITableViewCellStyleDefault
                    reuseIdentifier:@"channel"];
            }
            cell.messageIndicator.hidden = !channelAtRowIndex.unread;
            [cell.channelName setText:channelAtRowIndex.name];

            return cell;
        }
    }
    NSCAssert(0, @"Unexpected table view type");
    abort();
}

- (CGFloat)tableView:(UITableView *)tableView
    heightForHeaderInSection:(NSInteger)section {
    return (section == 0) ? 0 : 28.0;
}

- (UIView *)tableView:(UITableView *)tableView
    viewForHeaderInSection:(NSInteger)section {
    NSCAssert(section != 0, @"Unexpected section");

    UIView *headerView = [[UIView alloc]
        initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 28)];
    UIImageView *backgroundImageView =
        [[UIImageView alloc] initWithFrame:headerView.bounds];
    backgroundImageView.contentMode = UIViewContentModeScaleToFill;

    UILabel *label  = [[UILabel alloc]
        initWithFrame:CGRectMake(10, 5, tableView.frame.size.width - 20, 18)];
    label.textColor = [UIColor colorWithRed:158.0 / 255.0
                                      green:159.0 / 255.0
                                       blue:159.0 / 255.0
                                      alpha:1.0];

    backgroundImageView.image = [UIImage imageNamed:@"headerSeparator"];
    label.layer.shadowColor   = [UIColor blackColor].CGColor;
    label.layer.shadowOffset  = CGSizeMake(0, 1);
    label.backgroundColor     = [UIColor clearColor];
    label.font                = [UIFont boldSystemFontOfSize:16];


    [headerView addSubview:backgroundImageView];
    if (section == 1) {
        label.text = @"Chats";
    }

    [headerView addSubview:label];
    return headerView;
}


+ (NSString *)imageNameForStatus:(NSString *)status {
    if ([status isEqualToString:@"online"]) {
        return @"online";
    } else if ([status isEqualToString:@"dnd"]) {
        return @"dnd";
    } else if ([status isEqualToString:@"idle"]) {
        return @"absent";
    } else {
        return @"offline";
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView
    numberOfRowsInSection:(NSInteger)section {
    if (tableView == self.guildTableView && DCServerCommunicator.sharedInstance.guilds) {
        return DCServerCommunicator.sharedInstance.guilds.count;
    } else if (tableView == self.channelTableView && self.selectedGuild && self.selectedGuild.channels) {
        return self.selectedGuild.channels.count;
    } else {
        return 0;
    }
}

// SEGUE
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.destinationViewController class] != [DCChatViewController class]) {
        return;
    }
    if (![segue.identifier isEqualToString:@"guilds to chat"]) {
        return;
    }
    DCChatViewController *chatViewController =
        [segue destinationViewController];

    if (![chatViewController isKindOfClass:DCChatViewController.class]) {
        return;
    }
    DCChannel *selectedChannel =
        DCServerCommunicator.sharedInstance.selectedChannel;
        
    // Initialize messages
    [NSNotificationCenter.defaultCenter
    postNotificationName:@"NUKE CHAT DATA"
                  object:nil];
    [NSNotificationCenter.defaultCenter postNotificationName:@"GuildMemberListUpdated" object:nil];

    NSString *formattedChannelName;

    if (selectedChannel.type == 0) {
        formattedChannelName = [@"#"
            stringByAppendingString:selectedChannel.name];
    } else {
        formattedChannelName = selectedChannel.name;
    }
    [chatViewController.navigationItem
        setTitle:formattedChannelName];
    [chatViewController getMessages:50 beforeMessage:nil];
    [chatViewController setViewingPresentTime:true];
}
// SEGUE END
@end
