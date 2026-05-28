//
//  DCGuildFolder.h
//  Discord Classic
//
//  Created by plx on 7/13/25.
//  Copyright (c) 2025 plzdonthaxme. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <objc/NSObjCRuntime.h>
#import <UIKit/UIKit.h>

@interface DCGuildFolder : NSObject 

@property (strong, nonatomic) NSString *name;
@property (assign, nonatomic) NSInteger color;
@property (assign, nonatomic) NSInteger id;
@property (strong, nonatomic) NSArray *guildIds;
@property (assign, nonatomic) BOOL opened;
@property (strong, nonatomic) UIImage *icon;

@end