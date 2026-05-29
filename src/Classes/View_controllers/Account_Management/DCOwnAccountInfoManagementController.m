//
//  DCOwnAccountInfoManagementController.m
//  Discord Classic
//
//  Created by XML on 03/01/25.
//  Copyright (c) 2025 bag.xml. All rights reserved.
//

#import "DCOwnAccountInfoManagementController.h"
#include "DCUser.h"
#include <Foundation/Foundation.h>
#import "SDWebImageManager.h"

@interface DCOwnAccountInfoManagementController ()

@end

@implementation DCOwnAccountInfoManagementController

/*
 @property (weak, nonatomic) IBOutlet UIImageView *pfp;
 @property (weak, nonatomic) IBOutlet UIImageView *banner;

 @property (weak, nonatomic) IBOutlet UIView *bannerView;

 @property (weak, nonatomic) IBOutlet UILabel *pronouns;
 @property (weak, nonatomic) IBOutlet UILabel *username;
 @property (weak, nonatomic) IBOutlet UILabel *trueusername;

 @property (weak, nonatomic) IBOutlet UITextView *bio;

 @property (weak, nonatomic) IBOutlet UILabel *email;
 @property (weak, nonatomic) IBOutlet UILabel *phoneNumber;
 @property (weak, nonatomic) IBOutlet UILabel *userID;
 @property (weak, nonatomic) IBOutlet UITextField *token;

 userInfo[@"username"] = [d valueForKeyPath:@"user.username"];
 userInfo[@"global_name"] = [d valueForKeyPath:@"user.global_name"];
 userInfo[@"phone"] = [d valueForKeyPath:@"user.phone"];
 userInfo[@"email"] = [d valueForKeyPath:@"user.email"];
 userInfo[@"bio"] = [d valueForKeyPath:@"user.bio"];
 userInfo[@"banner"] = [d valueForKeyPath:@"user.banner"];
 userInfo[@"banner_color"] = [d valueForKeyPath:@"user.banner_color"];
 userInfo[@"clan"] = [d valueForKeyPath:@"user.clan"];
 userInfo[@"id"] = [d valueForKeyPath:@"user.id"];
 userInfo[@"connectedAccounts"] = [d valueForKeyPath:@"connected_accounts"];
 */

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar
        setBackgroundImage:[UIImage imageNamed:@"TbarBG"]
             forBarMetrics:UIBarMetricsDefault];
    self.navigationItem.title = [NSString
        stringWithFormat:@"Me (%@)", DCServerCommunicator.sharedInstance.currentUserInfo.globalName];
    [self.doneButton setBackgroundImage:[UIImage imageNamed:@"BarButton"]
                               forState:UIControlStateNormal
                             barMetrics:UIBarMetricsDefault];
    [self.doneButton setBackgroundImage:[UIImage imageNamed:@"BarButtonPressed"]
                               forState:UIControlStateHighlighted
                             barMetrics:UIBarMetricsDefault];

    DCUserInfo *userInfo =
        DCServerCommunicator.sharedInstance.currentUserInfo;

    self.trueusername.text = userInfo.username;
    self.username.text     = userInfo.globalName;
    self.pronouns.text     = userInfo.pronouns;

    self.bio.text = userInfo.bio;

    self.email.text = userInfo.email;
    if ([userInfo.phone isKindOfClass:[NSNull class]]) {
        self.phoneNumber.text = @"None";
    } else {
        self.phoneNumber.text = userInfo.phone;
    }

    self.userID.text = userInfo.id;
    dispatch_async(
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
        ^{
            NSURL *avatarURL = [NSURL
                URLWithString:[NSString
                                  stringWithFormat:
                                      @"https://cdn.discordapp.com/avatars/%@/%@.png?size=64",
                                      userInfo.id,
                                      userInfo.avatar]];

            SDWebImageManager *manager = [SDWebImageManager sharedManager];
            [manager downloadImageWithURL:avatarURL
                                  options:0
                                 progress:nil
                                completed:^(UIImage *retrievedImage, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) { @autoreleasepool {
                                    if (!retrievedImage || !finished) {
                                        NSLog(@"Failed to download avatar with URL %@: %@", avatarURL, error);
                                        return;
                                    }
                                    dispatch_async(
                                        dispatch_get_main_queue(),
                                        ^{
                                            self.pfp.image =
                                                retrievedImage;
                                            self.pfp.layer.cornerRadius =
                                                self.pfp.frame.size.width
                                                / 2.0;
                                            self.pfp.layer.masksToBounds =
                                                YES;
                                        }
                                    );
                                }}];
        }
    );

    if (userInfo.banner && ![userInfo.banner isKindOfClass:[NSNull class]]) {
        NSURL *url   = [NSURL
            URLWithString:[NSString
                              stringWithFormat:@"https://cdn.discordapp.com/banners/%@/%@.png?size=480",
                                               userInfo.id,
                                               userInfo.banner]];
        NSData *data = [NSData dataWithContentsOfURL:url];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.banner.image = [UIImage imageWithData:data];
        });
    } else {
        if (![userInfo.bannerColor isKindOfClass:[NSNull class]]) {
            UIColor *backgroundColor = [UIColorHex
                colorWithHexString:userInfo.bannerColor];
            if (backgroundColor) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.bannerView.backgroundColor = backgroundColor;
                });
            }
        }
    }


    NSDictionary *connections = userInfo.connectedAccounts;
    self.activeConnections    = connections;
    // Token

    self.token.text = DCServerCommunicator.sharedInstance.token;
}


- (NSInteger)tableView:(UITableView *)tableView
    numberOfRowsInSection:(NSInteger)section {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"hackyMode"] == NO) {
        if (self.activeConnections.count == 0) {
            self.noConnections = YES;
            return 1;
        } else {
            self.noConnections = NO;
            return self.activeConnections.count;
        }
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.noConnections == NO) {
        DCConnectedAccountsCell *cell =
            [tableView dequeueReusableCellWithIdentifier:@"Connection"];

        NSArray *accountsArray    = (NSArray *)self.activeConnections;
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

        } else if ([accountDict[@"type"] isEqualToString:@"contacts"]) {
            cell.type.text      = @"Contacts";
            cell.typeIcon.image = [UIImage imageNamed:@"C-Contacts"];

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


- (IBAction)return:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
