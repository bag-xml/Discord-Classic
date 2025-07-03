//
//  DCSettingsViewController.m
//  Discord Classic
//
//  Created by Trevir on 3/18/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import "DCSettingsViewController.h"
#import "DCServerCommunicator.h"
#import "DCTools.h"

@implementation DCSettingsViewController


- (void)viewDidLoad {
    [super viewDidLoad];

    NSString *token =
        [NSUserDefaults.standardUserDefaults stringForKey:@"token"];

    // Show current token in text field if one has previously been entered
    if (token) {
        [self.tokenInputField setText:token];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [NSUserDefaults.standardUserDefaults setObject:self.tokenInputField.text
                                            forKey:@"token"];

    // Save the entered values and reauthenticate if the token has been changed
    if (![DCServerCommunicator.sharedInstance.token
            isEqual:[NSUserDefaults.standardUserDefaults
                        valueForKey:@"token"]]) {
        DCServerCommunicator.sharedInstance.token = self.tokenInputField.text;
        [DCServerCommunicator.sharedInstance reconnect];
    }
}

- (IBAction)openTutorial:(id)sender {
    // Link to video describing how to enter your token
    [UIApplication.sharedApplication
        openURL:[NSURL URLWithString:
                           @"https://www.youtube.com/watch?v=NWB3fGafJwk"]];
}

- (void)tableView:(UITableView *)tableView
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == 1 && indexPath.section == 1) {
        [DCTools joinGuild:@"9WjXhTPyRf"];
        [self performSegueWithIdentifier:@"Settings to Test Channel"
                                  sender:self];
    }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"Settings to Test Channel"]) {
        DCChatViewController *chatViewController =
            [segue destinationViewController];

        if ([chatViewController isKindOfClass:DCChatViewController.class]) {
            DCServerCommunicator.sharedInstance.selectedChannel =
                [DCServerCommunicator.sharedInstance.channels
                    valueForKey:@"1184464173795651594"];

            // Initialize messages
            chatViewController.messages = NSMutableArray.new;

            [chatViewController.navigationItem
                setTitle:@"Discord Classic #general"];

            // Populate the message view with the last 50 messages
            // dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,
            // 0), ^{
            [chatViewController getMessages:50 beforeMessage:nil];
            //});

            // Chat view is watching the present conversation (auto scroll with
            // new messages)
            [chatViewController setViewingPresentTime:YES];
        }
    }
}

@end
