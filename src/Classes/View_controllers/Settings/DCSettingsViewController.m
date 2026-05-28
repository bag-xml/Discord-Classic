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
#import "DCCacheManager.h"
#import "WSWebSocket.h"

@implementation DCSettingsViewController


- (void)viewDidLoad {
    [super viewDidLoad];
    self.experimentalToggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"experimentalMode"];
    self.dataSaverToggle.on    = [[NSUserDefaults standardUserDefaults] boolForKey:@"dataSaver"];

    NSString *token =
        [NSUserDefaults.standardUserDefaults stringForKey:@"token"];

    // Show current token in text field if one has previously been entered
    if (token) {
        [self.tokenInputField setText:token];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    // Don't persist or reconnect if we're logging out
    if (self.isLoggingOut) return;

    NSString *enteredToken = self.tokenInputField.text;
    if (enteredToken.length > 0) {
        [NSUserDefaults.standardUserDefaults setObject:enteredToken forKey:@"token"];
    } else {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"token"];
    }

    if (![DCServerCommunicator.sharedInstance.token
            isEqualToString:[NSUserDefaults.standardUserDefaults stringForKey:@"token"]]) {
        DCServerCommunicator.sharedInstance.token = enteredToken;
        [DCServerCommunicator.sharedInstance reconnect];
    }
}

- (IBAction)openTutorial:(id)sender {
    // Link to video describing how to enter your token
    [UIApplication.sharedApplication
        openURL:[NSURL URLWithString:
                           @"https://www.youtube.com/watch?v=NWB3fGafJwk"]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row == 1 && indexPath.section == 1) {
        [DCTools joinGuild:@"9WjXhTPyRf"];
        [self performSegueWithIdentifier:@"Settings to Test Channel" sender:self];
    }

    // TODO: fill in the correct section/row for your logout cell
    if (indexPath.row == 0 && indexPath.section == 3) {
        [self didTapLogOut];
    }
}

- (IBAction)didTapLogOut {
    UIAlertView *alert = [[UIAlertView alloc]
        initWithTitle:@"Log Out"
              message:@"Are you sure you want to log out?"
             delegate:self
    cancelButtonTitle:@"No"
    otherButtonTitles:@"Yes", nil];
    alert.tag = 99; // distinguish from restart alerts
    [alert show];
}

- (IBAction)experimentalSwitchChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"experimentalMode"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    UIAlertView *alert = [[UIAlertView alloc]
        initWithTitle:@"Restart Required"
              message:@"Toggling Experimental Mode requires an app restart. Would you like to restart now?"
             delegate:self
    cancelButtonTitle:@"No"
    otherButtonTitles:@"Yes", nil];
    [alert show];
}

- (IBAction)dataSaverSwitchChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"dataSaver"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    UIAlertView *alert = [[UIAlertView alloc]
        initWithTitle:@"Restart Required"
              message:@"Toggling Data Saver Mode requires an app restart. Would you like to restart now?"
             delegate:self
    cancelButtonTitle:@"No"
    otherButtonTitles:@"Yes", nil];
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 99) {
        // Logout confirmation
        if (buttonIndex == 1) {
            [self performLogOut];
        }
        return;
    }
    if (buttonIndex == 1) {
        exit(0);
    }
}

- (void)performLogOut {
    self.isLoggingOut = YES;

    DCServerCommunicator *comm = DCServerCommunicator.sharedInstance;
    
    // Nil token first so any callbacks during teardown can't trigger a reconnect
    comm.token           = nil;
    comm.didAuthenticate = NO;

    // Tear down connection state cleanly
    [comm prepareForLogout];

    // Clear data
    comm.currentUserInfo     = nil;
    comm.guilds              = nil;
    comm.channels            = nil;
    comm.loadedUsers         = nil;
    comm.loadedRoles         = nil;
    comm.loadedEmojis        = nil;
    comm.selectedGuild       = nil;
    comm.selectedChannel     = nil;
    comm.userChannelSettings = nil;

    self.tokenInputField.text = @"";
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"token"];
    [NSUserDefaults.standardUserDefaults synchronize];

    [[DCCacheManager sharedInstance] invalidateAllMessages];
    [[DCCacheManager sharedInstance] handleMemoryWarning];

    [[NSNotificationCenter defaultCenter] postNotificationName:@"DCUserDidLogOut" object:nil];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"Settings to Test Channel"]) {
        DCChatViewController *chatViewController =
            [segue destinationViewController];

        if ([chatViewController isKindOfClass:DCChatViewController.class]) {
            DCServerCommunicator.sharedInstance.selectedChannel =
                [DCServerCommunicator.sharedInstance.channels
                    objectForKey:@"1184464173795651594"];

            // Initialize messages
            [NSNotificationCenter.defaultCenter
                postNotificationName:@"NUKE CHAT DATA"
                              object:nil];

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
