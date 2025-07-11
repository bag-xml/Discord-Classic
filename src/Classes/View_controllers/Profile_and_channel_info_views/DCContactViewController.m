//
//  DCContactViewController.m
//  Discord Classic
//
//  Created by bag.xml on 27/01/24.
//  Copyright (c) 2024 bag.xml. All rights reserved.
//

#import "DCContactViewController.h"


@interface DCContactViewController ()

@property DCUser *user;
@property (weak, nonatomic) IBOutlet UIImageView *profileImageView;
@property (weak, nonatomic) IBOutlet UIView *bannerView;
@property (weak, nonatomic) IBOutlet UIImageView *profileBanner;
@property (weak, nonatomic) IBOutlet UILabel *nameLabel;
@property (weak, nonatomic) IBOutlet UILabel *handleLable;
@property (weak, nonatomic) IBOutlet UITextView *descriptionBox;
@property (weak, nonatomic) IBOutlet UIImageView *statusIcon;
@end

@implementation DCContactViewController

- (void)viewWillAppear:(BOOL)animated {
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navBar setBackgroundImage:[UIImage imageNamed:@"TbarBG"]
                      forBarMetrics:UIBarMetricsDefault];
    [self.doneButton setBackgroundImage:[UIImage imageNamed:@"BarButton"]
                               forState:UIControlStateNormal
                             barMetrics:UIBarMetricsDefault];
    [self.doneButton setBackgroundImage:[UIImage imageNamed:@"BarButtonPressed"]
                               forState:UIControlStateHighlighted
                             barMetrics:UIBarMetricsDefault];

    self.conTableView.delegate              = self;
    self.conTableView.dataSource            = self;
    self.slideMenuController.gestureSupport = NO;
}

- (void)setSelectedUser:(DCUser *)user {
    // pre-init
    self.view                 = self.view;
    self.navigationItem.title = user.globalName;
    self.nameLabel.text       = user.globalName;
    self.handleLable.text     = user.username;
    self.snowflake            = user.snowflake;
    self.statusIcon.image =
        [UIImage imageNamed:[self imageNameForStatus:user.status]];
    // image
    self.profileImageView.image = user.profileImage;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"hackyMode"] == NO) {
        self.profileImageView.layer.cornerRadius =
            self.profileImageView.frame.size.width / 2.0;
    }
    self.profileImageView.layer.masksToBounds = YES;

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"hackyMode"] == NO) {
        dispatch_async(
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
            ^{
                NSURL *userProfileURL           = [NSURL
                    URLWithString:
                        [NSString
                            stringWithFormat:
                                @"https://discordapp.com/api/v9/users/%@/"
                                          @"profile?with_mutual_guilds=false&with_mutual_"
                                          @"friends=true&with_mutual_friends_count=false",
                                user.snowflake]];
                NSMutableURLRequest *urlRequest = [NSMutableURLRequest
                     requestWithURL:userProfileURL
                        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                    timeoutInterval:15];
                [urlRequest setValue:@"no-store"
                    forHTTPHeaderField:@"Cache-Control"];
                [urlRequest addValue:DCServerCommunicator.sharedInstance.token
                    forHTTPHeaderField:@"Authorization"];
                [urlRequest addValue:@"application/json"
                    forHTTPHeaderField:@"Content-Type"];
                NSHTTPURLResponse *responseCode = nil;

                NSError *error = nil;
                NSData *response =
                    [DCTools checkData:[NSURLConnection
                                           sendSynchronousRequest:urlRequest
                                                returningResponse:&responseCode
                                                            error:&error]
                             withError:error];
                if (response) {
                    NSDictionary *parsedResponse =
                        [NSJSONSerialization JSONObjectWithData:response
                                                        options:0
                                                          error:&error];
                    if (error) {
                        return;
                    }
                    NSDictionary *userProfile =
                        [parsedResponse objectForKey:@"user_profile"];
                    NSDictionary *userInfo =
                        [parsedResponse objectForKey:@"user"];

                    self.connectedAccounts =
                        [parsedResponse objectForKey:@"connected_accounts"];
                    self.mutualFriends =
                        [parsedResponse objectForKey:@"mutual_friends"];

                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.pronounLabel.text =
                            [userProfile objectForKey:@"pronouns"];
                        self.descriptionBox.text =
                            [userProfile valueForKey:@"bio"];
                        [self.conTableView reloadData];
                    });

                    NSString *bannerHash = [userInfo objectForKey:@"banner"];
                    NSString *bannerHexCode =
                        [userInfo objectForKey:@"banner_color"];

                    if (bannerHash
                        && ![bannerHash isKindOfClass:[NSNull class]]) {
                        NSURL *url   = [NSURL
                            URLWithString:[NSString
                                              stringWithFormat:
                                                  @"https://cdn.discordapp.com/"
                                                    @"banners/%@/%@.png?size=480",
                                                  [userInfo objectForKey:@"id"],
                                                  [userInfo
                                                      objectForKey:@"banner"]]];
                        NSData *data = [NSData dataWithContentsOfURL:url];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            self.profileBanner.image =
                                [UIImage imageWithData:data];
                        });
                    } else {
                        if (![bannerHexCode isKindOfClass:[NSNull class]]) {
                            UIColor *backgroundColor =
                                [UIColorHex colorWithHexString:bannerHexCode];
                            if (backgroundColor) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    self.bannerView.backgroundColor =
                                        backgroundColor;
                                    [self.conTableView reloadData];
                                });
                            }
                        }
                    }
                } else {
                }
            }
        );
    }
}


// buttons
- (IBAction)throwToChat:(id)sender {
    [self performSegueWithIdentifier:@"about to chat" sender:self];
}

/*table view*/
- (NSInteger)tableView:(UITableView *)tableView
    numberOfRowsInSection:(NSInteger)section {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"hackyMode"] == NO) {
        if (self.connectedAccounts.count == 0) {
            self.noConnections = YES;
            return 1;
        } else {
            self.noConnections = NO;
            return self.connectedAccounts.count;
        }
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.noConnections == NO) {
        DCConnectedAccountsCell *cell =
            [tableView dequeueReusableCellWithIdentifier:@"Connection"];

        NSArray *accountsArray    = (NSArray *)self.connectedAccounts;
        NSDictionary *accountDict = accountsArray[indexPath.row];
        cell.name.text            = accountDict[@"name"];

        // steam, playstation, domain

        if ([accountDict[@"type"] isEqualToString:@"youtube"]) {
            cell.type.text      = @"YouTube";
            cell.typeIcon.image = [UIImage imageNamed:@"C-YouTube"];

        } else if ([accountDict[@"type"] isEqualToString:@"twitter"]) {
            cell.type.text      = @"Twitter";
            cell.typeIcon.image = [UIImage imageNamed:@"C-Twitter"];

        } else if ([accountDict[@"type"] isEqualToString:@"bluesky"]) {
            cell.type.text      = @"BlueSky";
            cell.typeIcon.image = [UIImage imageNamed:@"C-BlueSky"];

        } else if ([accountDict[@"type"] isEqualToString:@"twitch"]) {
            cell.type.text      = @"Twitch";
            cell.typeIcon.image = [UIImage imageNamed:@"C-Twitch"];

        } else if ([accountDict[@"type"] isEqualToString:@"reddit"]) {
            cell.type.text      = @"Reddit";
            cell.typeIcon.image = [UIImage imageNamed:@"C-Reddit"];

        } else if ([accountDict[@"type"] isEqualToString:@"xbox"]) {
            cell.type.text      = @"Xbox-Live";
            cell.typeIcon.image = [UIImage imageNamed:@"C-Xbox"];

        } else if ([accountDict[@"type"] isEqualToString:@"steam"]) {
            cell.type.text      = @"Steam";
            cell.typeIcon.image = [UIImage imageNamed:@"C-Steam"];

        } else if ([accountDict[@"type"] isEqualToString:@"playstation"]) {
            cell.type.text      = @"PlayStationNetwork";
            cell.typeIcon.image = [UIImage imageNamed:@"C-PSN"];

        } else if ([accountDict[@"type"] isEqualToString:@"domain"]) {
            cell.type.text      = @"Domain/Website";
            cell.typeIcon.image = [UIImage imageNamed:@"C-Web"];

        } else if ([accountDict[@"type"] isEqualToString:@"spotify"]) {
            cell.type.text      = @"Spotify";
            cell.typeIcon.image = [UIImage imageNamed:@"C-Spotify"];

        } else if ([accountDict[@"type"] isEqualToString:@"github"]) {
            cell.type.text      = @"GitHub";
            cell.typeIcon.image = [UIImage imageNamed:@"C-GitHub"];

        } else {
            cell.typeIcon.image = [UIImage imageNamed:@"C-Web"];
            cell.type.text      = accountDict[@"type"];
        }

        return cell;
    } else if (self.noConnections == YES) {
        UITableViewCell *cell =
            [tableView dequeueReusableCellWithIdentifier:@"No-Connection"];
        if (!cell) {
            cell = UITableViewCell.new;
        }
        return cell;
    }
    NSAssert(0, @"Unexpected state");
    abort();
}

- (CGFloat)tableView:(UITableView *)tableView
    heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 120;
}

- (IBAction)throwToMutualFriends:(id)sender {
    [self performSegueWithIdentifier:@"about to mutual friends" sender:self];
}


- (NSString *)imageNameForStatus:(NSString *)status {
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

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"about to chat"]) {
        DCChatViewController *chatViewController =
            [segue destinationViewController];
        if ([chatViewController isKindOfClass:DCChatViewController.class]) {
            DCChannel *privateChannel =
                [self findPrivateChannelForUser:self.snowflake];

            if (privateChannel) {
                DCServerCommunicator.sharedInstance.selectedChannel =
                    privateChannel;
                // NSString *formattedChannelName = privateChannel.name;

                [NSNotificationCenter.defaultCenter
                postNotificationName:@"NUKE CHAT DATA"
                              object:nil];

                [chatViewController getMessages:50 beforeMessage:nil];
                [chatViewController setViewingPresentTime:true];
            } else {
            }
        }
    } else if ([segue.identifier isEqualToString:@"about to mutual friends"]) {
        if ([segue.destinationViewController class] ==
            [DCMutualFriendsViewController class]) {
            DCMutualFriendsViewController *friendmutualVC =
                (DCMutualFriendsViewController *)
                    segue.destinationViewController;
            friendmutualVC.mutualFriendsList = self.mutualFriends;
        }
    }
}

- (DCChannel *)findPrivateChannelForUser:(NSString *)userId {
    for (DCGuild *guild in DCServerCommunicator.sharedInstance.guilds) {
        if ([guild.name isEqualToString:@"Direct Messages"]) {
            for (DCChannel *channel in guild.channels) {
                for (NSDictionary *userDict in channel.users) {
                    if ([userDict[@"snowflake"] isEqualToString:userId]) {
                        return channel;
                    }
                }
            }
        }
    }
    return nil;
}
- (IBAction)clickedDone:(id)sender {
    [self dismissModalViewControllerAnimated:YES];
}

@end
