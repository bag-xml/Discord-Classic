//
//  DCAppDelegate.m
//  Discord Classic
//
//  Created by bag.xml on 3/2/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import "DCAppDelegate.h"
#include "SDWebImageManager.h"
#include <UIKit/UIKit.h>
#import "UIDeviceAdditions.h"
#import "DCServerCommunicator.h"
#import "DCUser.h"
#import "DCRole.h"
#import "DCServerCommunicator.h"

@interface DCAppDelegate ()
@property (assign, nonatomic) BOOL shouldReload;
@end

@implementation DCAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // [NSTimer scheduledTimerWithTimeInterval:2.0
    //     target:[UIDevice currentDevice]
    //     selector:@selector(currentMemoryUsage)
    //     userInfo:nil
    //     repeats:YES];

    // App version reporting
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
//    NSString *build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    [[NSUserDefaults standardUserDefaults] setObject:[NSString stringWithFormat:@"%@", version]
                                              forKey:@"version"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleLogOut)
                                                 name:@"DCUserDidLogOut"
                                               object:nil];

    self.window.backgroundColor = [UIColor clearColor];
    self.window.opaque          = NO;
    self.shouldReload           = false;
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (VERSION_MIN(@"7.0")) {
        [[NSUserDefaults standardUserDefaults] setBool:YES
                                                forKey:@"UIUseLegacyUI"];
    }

    self.experimental = [[NSUserDefaults standardUserDefaults] boolForKey:@"experimentalMode"];
    self.hackyMode = [[NSUserDefaults standardUserDefaults] boolForKey:@"hackyMode"];

    if (self.experimental && self.hackyMode) {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"hackyMode"];
    }

    // if (NSFoundationVersionNumber > NSFoundationVersionNumber_iOS_6_1) {
    //     UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard-7" bundle:nil];
    //     UIViewController *initialViewController = [storyboard instantiateInitialViewController];
    //     self.window.rootViewController = initialViewController;
    //     [self.window makeKeyAndVisible];
    if (self.experimental) {
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Experimental" bundle:nil];
        UIViewController *initialViewController = [storyboard instantiateInitialViewController];
        self.window.rootViewController = initialViewController;
        [self.window makeKeyAndVisible];
    } else if (self.hackyMode) {
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Throwback" bundle:nil];
        UIViewController *initialViewController = [storyboard instantiateInitialViewController];
        self.window.rootViewController = initialViewController;
        [self.window makeKeyAndVisible];
        [UINavigationBar.appearance
            setBackgroundImage:[UIImage imageNamed:@"OldTitlebarTexture"]
                 forBarMetrics:UIBarMetricsDefault];
    }

    NSURLCache *urlCache = [[NSURLCache alloc]
        initWithMemoryCapacity:1024 * 1024 * 8  // 8MB mem cache
                  diskCapacity:1024 * 1024 * 60 // 60MB disk cache
                      diskPath:nil];
    [NSURLCache setSharedURLCache:urlCache];
    application.applicationIconBadgeNumber = 0;
    [SDWebImageManager sharedManager].imageCache.maxMemoryCost = 1024 * 1024 * 20; // 20MB for decoded images
    [SDWebImageManager sharedManager].imageCache.maxMemoryCountLimit = 50; // max 50 images in memory

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("dis.cord.Discord.badgeReset"), NULL, NULL, true
    );

    if (launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey]) {
        NSDictionary *notification = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
        NSDictionary *aps          = notification[@"aps"];
        NSString *channelId        = aps[@"channelId"]; // Adjusted to reflect your payload structure
        // NSLog(@"Channel id: %@", channelId);
        if (channelId) {
            // NSLog(@"App launched with notification, channelId: %@",
            // channelId);
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                dispatch_get_main_queue(),
                ^{
                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:@"NavigateToChannel"
                                      object:nil
                                    userInfo:@{@"channelId" : channelId}];
                }
            );
        }
    }

    if (DCServerCommunicator.sharedInstance.token.length) {
        [DCServerCommunicator.sharedInstance startCommunicator];
    }
    
    UIImage *backNormal = [[UIImage imageNamed:@"NavigationButton"]
     resizableImageWithCapInsets:UIEdgeInsetsMake(0, 14, 0, 6)];
    
    UIImage *backPressed = [[UIImage imageNamed:@"NavigationButtonPressed"]
     resizableImageWithCapInsets:UIEdgeInsetsMake(0, 14, 0, 6)];
    
    [[UIBarButtonItem appearance] setBackButtonBackgroundImage:backNormal
                                                      forState:UIControlStateNormal
                                                    barMetrics:UIBarMetricsDefault];
    
    [[UIBarButtonItem appearance] setBackButtonBackgroundImage:backPressed
                                                      forState:UIControlStateHighlighted
                                                    barMetrics:UIBarMetricsDefault];
    
    [[UIApplication sharedApplication] registerForRemoteNotificationTypes:
     UIRemoteNotificationTypeBadge |
     UIRemoteNotificationTypeSound |
     UIRemoteNotificationTypeAlert];
    
    return YES;
}


- (void)application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo {
    // NSLog(@"RECEIVED REMOTE NOTIFICATION");

    NSDictionary *aps   = userInfo[@"aps"];
    NSString *channelId = aps[@"channelId"];
    // NSLog(@"Received notification with Channel id: %@", channelId);

    if (channelId) {
        UIApplicationState state = [application applicationState];
        if (state == UIApplicationStateInactive
            || state == UIApplicationStateBackground) {
            // App was in the background or not running, meaning the user tapped
            // the notification
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:@"NavigateToChannel"
                                  object:nil
                                userInfo:@{@"channelId" : channelId}];
            });
        } else {
            // NSLog(@"FUCK YOU LJB I HATE YOU");
            // ok requis
        }
    }
}

- (void)application:(UIApplication *)application
didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    
    NSMutableString *token = [NSMutableString stringWithCapacity:deviceToken.length * 2];
    const unsigned char *bytes = deviceToken.bytes;
    for (NSInteger i = 0; i < deviceToken.length; i++) {
        [token appendFormat:@"%02x", bytes[i]];
    }
    
    NSLog(@"APNs device token: %@", token);
    [DCServerCommunicator.sharedInstance registerPushToken:token];
}

- (void)application:(UIApplication *)application
didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    NSLog(@"Failed to register for push: %@", error);
}

- (void)handleLogOut {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:self.experimental ? @"Experimental" : @"Storyboard" bundle:nil];
    UIViewController *freshRoot = [storyboard instantiateInitialViewController];

    self.loggingOut = YES;
    [freshRoot view];
    [freshRoot.view layoutIfNeeded];
    
    [UIView transitionWithView:self.window
                      duration:0.8
                       options:UIViewAnimationOptionTransitionFlipFromLeft
                    animations:^{
                        self.window.rootViewController = freshRoot;
                    }
                    completion:nil];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    [[NSUserDefaults standardUserDefaults] synchronize];
    // NSLog(@"Will resign active");
}


- (void)applicationDidEnterBackground:(UIApplication *)application {
    // NSLog(@"Did enter background");
    [[NSUserDefaults standardUserDefaults] synchronize];
    self.shouldReload = DCServerCommunicator.sharedInstance.didAuthenticate;
}


- (void)applicationWillEnterForeground:(UIApplication *)application {
    // NSLog(@"Will enter foreground");
    [[NSUserDefaults standardUserDefaults] synchronize];
}


- (void)applicationDidBecomeActive:(UIApplication *)application {
    // NSLog(@"Did become active");
    [[NSUserDefaults standardUserDefaults] synchronize];
    // if (self.shouldReload) {
    //     [DCServerCommunicator.sharedInstance sendResume];
    // }
}


- (void)applicationWillTerminate:(UIApplication *)application {
    [[NSUserDefaults standardUserDefaults] synchronize];
    // NSLog(@"Will terminate");
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {
    NSLog(@"Memory warning received, clearing image cache!");
    // for (DCUser *user in DCServerCommunicator.sharedInstance.loadedUsers.allValues) {
    //     @autoreleasepool {
    //         user.profileImage = nil;
    //         user.avatarDecoration = nil;
    //     }
    // }
    // for (DCRole *role in DCServerCommunicator.sharedInstance.loadedRoles.allValues) {
    //     @autoreleasepool {
    //         role.icon = nil;
    //     }
    // }
    [[UIDevice currentDevice] currentMemoryUsage];
    [SDWebImageManager.sharedManager.imageCache clearMemory];
}

@end
