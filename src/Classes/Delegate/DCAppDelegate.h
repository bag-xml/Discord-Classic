//
//  DCAppDelegate.h
//  Discord Classic
//
//  Created by bag.xml on 3/2/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DCServerCommunicator.h"
#import "DCTools.h"

@interface DCAppDelegate : UIResponder<UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property bool experimental;
@property bool hackyMode;
@end
