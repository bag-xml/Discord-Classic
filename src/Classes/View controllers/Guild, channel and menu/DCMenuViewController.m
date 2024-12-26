//
//  DCMenuViewController.m
//  Discord Classic
//
//  Created by bag.xml on 27/01/24.
//  Copyright (c) 2024 Julian Triveri. All rights reserved.
//

#import "DCMenuViewController.h"

@interface DCMenuViewController ()


@end

@implementation DCMenuViewController

- (void)viewDidLoad{
	[super viewDidLoad];
	
    
	//Go to settings if no token is set
	if(!DCServerCommunicator.sharedInstance.token.length)
		[self performSegueWithIdentifier:@"to Tokenpage" sender:self];
	
    //NOTIF OBSERVERS
    
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleReady) name:@"READY" object:nil];
	
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleReady) name:@"MESSAGE ACK" object:nil];
	
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleMessageAck) name:@"MESSAGE ACK" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleMessageAck) name:@"RELOAD CHANNEL LIST" object:nil];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleReady) name:@"RELOAD GUILD LIST" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleMessageAck) name:@"MESSAGE ACK" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleMessageAck) name:@"RELOAD CHANNEL LIST" object:nil];
    //pns observers
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNotificationTap:) name:@"NavigateToChannel" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(exitedChatController) name:@"ChannelSelectionCleared" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handlePresenceRefresh)
                                                 name:@"USER_PRESENCE_UPDATED"
                                               object:nil];
    //NOTIF OBSERVERS END
    
    //TOOLBAR IMAGE LOGIC
    UIImage *toolbarBGImage = [UIImage imageNamed:@"ToolbarBG"];
    
    [self.toolbar setBackgroundImage:toolbarBGImage forToolbarPosition:UIToolbarPositionAny barMetrics:UIBarMetricsDefault];
    //toolbar image logic end
}


//block that handles what the app does if you open it via a push ntoification

- (void)handlePresenceRefresh {
    // This will force the channel list table to re-fetch each DM buddy’s status from loadedUsers
    [self.channelTableView reloadData];
}

- (void)handleNotificationTap:(NSNotification *)notification {
    //NSLog(@"HANDLE NOTIFICATION TAP CALLED");
    NSString *channelId = notification.userInfo[@"channelId"];
    if (channelId) {
        //NSLog(@"Navigating to channel with ID: %@", channelId);
        [self navigateToChannelWithId:channelId];
    }
}

-(void)exitedChatController {
    //NSLog(@"EXITING CHAT VIEW");
    self.selectedChannel = nil;
}

- (void)navigateToChannelWithId:(NSString *)channelId {
    for (DCGuild *guild in DCServerCommunicator.sharedInstance.guilds) {
        for (DCChannel *channel in guild.channels) {
            if ([channel.snowflake isEqualToString:channelId]) {
                //NSLog(@"channel id: %@", channelId);
                if (self.selectedChannel && [self.selectedChannel.snowflake isEqualToString:channelId]) {
                    //NSLog(@"ok");
                    return;
                }
                self.selectedGuild = guild;
                self.selectedChannel = channel;
                DCServerCommunicator.sharedInstance.selectedChannel = channel;
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self performSegueWithIdentifier:@"guilds to chat" sender:self];
                });
                return;
            }
        }
    }
}
//end of block

//reload
/*- (void)handleReady {
    [self.guildTableView reloadData];
    [self.channelTableView reloadData];
}*/

- (void)handleReady {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.guildTableView reloadData];
        [self.channelTableView reloadData];
        
        if(VERSION_MIN(@"6.0") && !self.refreshControl){
            self.refreshControl = UIRefreshControl.new;
            self.reloadControl = UIRefreshControl.new;
            
            self.reloadControl.attributedTitle = [[NSAttributedString alloc] initWithString:@"Reload"];
            self.refreshControl.attributedTitle = [[NSAttributedString alloc] initWithString:@"Reauthenticate"];
            
            [self.guildTableView addSubview:self.refreshControl];
            [self.channelTableView addSubview:self.reloadControl];
            
            [self.reloadControl addTarget:self action:@selector(reloadTable) forControlEvents:UIControlEventValueChanged];
            [self.refreshControl addTarget:self action:@selector(reconnect) forControlEvents:UIControlEventValueChanged];
        }
    });
}

- (void)reloadTable {
    [self.channelTableView reloadData];
    if (VERSION_MIN(@"6.0"))
        [self.reloadControl endRefreshing];
}

- (void)reconnect {
	[DCServerCommunicator.sharedInstance reconnect];
    if (VERSION_MIN(@"6.0"))
        [self.refreshControl endRefreshing];
}

//reload end
//misc
- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
}

- (void)handleMessageAck {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.channelTableView reloadData];
    });
}

//idk what to do with this ngl
-(void)viewWillAppear:(BOOL)animated{
    if (self.selectedGuild) {
        [self.channelTableView reloadData];
        [DCServerCommunicator.sharedInstance setSelectedChannel:nil];
        [self.channelTableView reloadData];
        if ([self.navigationItem.title isEqualToString:@"Direct Messages"]) {
            NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"lastMessageId" ascending:NO selector:@selector(localizedStandardCompare:)];
            [self.selectedGuild.channels sortUsingDescriptors:@[sortDescriptor]];
            
            [self.channelTableView reloadData];
        }
    } else {
        [self.navigationItem setTitle:@"Discord"];
    }
}

//misc end
- (IBAction)moreInfo:(id)sender {
    UIActionSheet *messageActionSheet = [[UIActionSheet alloc] initWithTitle:self.selectedGuild.name delegate:self cancelButtonTitle:@"Okay" destructiveButtonTitle:nil otherButtonTitles:nil, nil];
    [messageActionSheet setDelegate:self];
    [messageActionSheet showInView:self.view];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	
	if(tableView == self.guildTableView){
		self.selectedGuild = [DCServerCommunicator.sharedInstance.guilds objectAtIndex:indexPath.row];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        if(self.selectedGuild.banner == nil) {
            self.guildBanner.image = [UIImage imageNamed:@"ServerBanner"];
        } else {
            self.guildBanner.image = self.selectedGuild.banner;
        }
        [self.navigationItem setTitle:self.selectedGuild.name];
        self.guildLabel.text = self.selectedGuild.name;
		[self.channelTableView reloadData];
	}
    
    if(tableView == self.channelTableView){
        self.selectedChannel = (DCChannel*)[self.selectedGuild.channels objectAtIndex:indexPath.row];
        DCServerCommunicator.sharedInstance.selectedChannel = [self.selectedGuild.channels objectAtIndex:indexPath.row];
        
        //Mark channel messages as read and refresh the channel object accordingly
        [DCServerCommunicator.sharedInstance.selectedChannel ackMessage:DCServerCommunicator.sharedInstance.selectedChannel.lastMessageId];
        [DCServerCommunicator.sharedInstance.selectedChannel checkIfRead];
        
        //Remove the blue indicator since the channel has been read
        //[[self.channelTableView cellForRowAtIndexPath:indexPath] setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self performSegueWithIdentifier:@"guilds to chat" sender:self];
        
        //[tableView cellForRowAtIndexPath:indexPath].accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == self.guildTableView) {
        // Use the DCGuildTableViewCell
        DCGuildTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"guild"];
        if (cell == nil) {
            cell = [[DCGuildTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"guild"];
        }
        
        // Sorting guilds
        DCServerCommunicator.sharedInstance.guilds = [[DCServerCommunicator.sharedInstance.guilds sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            NSString *first = [(DCGuild *)a name];
            NSString *second = [(DCGuild *)b name];
            if ([first compare:@"Direct Messages"] == 0) return false; // DMs at the top
            return [first compare:second];
        }] mutableCopy];
        
        DCGuild *guildAtRowIndex = [DCServerCommunicator.sharedInstance.guilds objectAtIndex:indexPath.row];
        
        // Show blue indicator if guild has any unread messages
        cell.unreadMessages.hidden = !guildAtRowIndex.unread;
        
        // Guild name and icon
        [cell.guildAvatar setImage:guildAtRowIndex.icon];
        
        cell.guildAvatar.layer.cornerRadius = cell.guildAvatar.frame.size.width / 6.0;
        cell.guildAvatar.layer.masksToBounds = YES;
        
        return cell;
    }
    
    if (tableView == self.channelTableView) {
        DCChannelViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"channel"];
        if (cell == nil) {
            cell = [[DCChannelViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"channel"];
        }
        
        DCChannel *channelAtRowIndex = [self.selectedGuild.channels objectAtIndex:indexPath.row];
        cell.messageIndicator.hidden = !channelAtRowIndex.unread;
        [cell.channelName setText:channelAtRowIndex.name];
        
        // Presence indicator logic for DM channels (type 1)
        if (channelAtRowIndex.type == 1) {
            DCUser *buddy = nil;
            
            // Loop through users to find the DM partner
            for (NSDictionary *userDict in channelAtRowIndex.users) {
                NSString *userId = [userDict valueForKey:@"snowflake"];
                
                if (![userId isEqualToString:DCServerCommunicator.sharedInstance.snowflake]) {
                    buddy = [DCServerCommunicator.sharedInstance.loadedUsers objectForKey:userId];
                    
                    if (buddy) {
                        //NSLog(@"[Presence] Found buddy: %@ (ID: %@, Status: %@)", buddy.username, buddy.snowflake, buddy.status);
                    } else {
                        //NSLog(@"[Presence] User with ID %@ not found in loadedUsers.", userId);
                    }
                    
                    break;
                }
            }
            
            if (buddy) {
                // Get the color for the user's current status
                UIColor *dotColor = [self colorForUserStatus:buddy.status ?: @"offline"];
                cell.activityIndicatorLed.image = [self drawStatusDotWithColor:dotColor];
                //NSLog(@"[Presence] Status dot color for %@: %@", buddy.username, dotColor);
            } else {
                // Default to gray if user is not found
                //NSLog(@"[Presence] No buddy found, defaulting to gray.");
                cell.activityIndicatorLed.image = [self drawStatusDotWithColor:[UIColor grayColor]];
            }
        } else {
            // Non-DM channels do not need a status indicator
            cell.activityIndicatorLed.image = nil;
        }
        
        return cell;
    }
}


/*- (void)tableView:(UITableView *)tableView willDisplayCell:(DCGuildTableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath{
    // make guild icons a fixed size
    if(tableView == self.guildTableView) {
    cell.guildAvatar.frame = CGRectMake(0, 0, 32, 32);
    cell.guildAvatar.layer.cornerRadius = cell.imageView.frame.size.height / 4.0;
    cell.guildAvatar.layer.masksToBounds = YES;
    [cell.guildAvatar setNeedsDisplay];
    [cell layoutIfNeeded];
    }
}
*/
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	
	if(tableView == self.guildTableView)
    {return DCServerCommunicator.sharedInstance.guilds.count;}
	
    if(tableView == self.channelTableView)
        return self.selectedGuild.channels.count;
    
    return 0;
}

//SEGUE
- (void) prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender{
    if([segue.destinationViewController class] == [DCChatViewController class]){
        if ([segue.identifier isEqualToString:@"guilds to chat"]){
            DCChatViewController *chatViewController = [segue destinationViewController];
            
            if ([chatViewController isKindOfClass:DCChatViewController.class]){
                
                //Initialize messages
                chatViewController.messages = NSMutableArray.new;
                NSString* formattedChannelName;
                
                if(DCServerCommunicator.sharedInstance.selectedChannel.type == 0)
                    formattedChannelName = [@"#" stringByAppendingString:DCServerCommunicator.sharedInstance.selectedChannel.name];
                else
                    formattedChannelName = DCServerCommunicator.sharedInstance.selectedChannel.name;
                [chatViewController.navigationItem setTitle:formattedChannelName];
                [chatViewController getMessages:50 beforeMessage:nil];
                [chatViewController setViewingPresentTime:true];
            }
        }
        
    }
}
//SEGUE END

- (UIImage *)drawStatusDotWithColor:(UIColor *)color {
    CGFloat dotSize = 14.0;
    CGRect rect = CGRectMake(0.0, 0.0, dotSize, dotSize);
    
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    CGContextSetFillColorWithColor(context, color.CGColor);
    CGContextFillEllipseInRect(context, rect);
    
    UIImage *statusDot = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return statusDot;
}

- (UIColor *)colorForUserStatus:(NSString *)status {
    if ([status isEqualToString:@"online"]) {
        return [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:1.0];  // Green
    } else if ([status isEqualToString:@"dnd"]) {
        return [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0];  // Red
    } else if ([status isEqualToString:@"idle"]) {
        return [UIColor colorWithRed:1.0 green:0.65 blue:0.0 alpha:1.0]; // Orange
    } else {
        return [UIColor colorWithWhite:0.6 alpha:1.0];  // Gray (offline)
    }
}

@end
