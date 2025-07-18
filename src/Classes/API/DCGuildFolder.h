//
//  DCGuildFolder.h
//  Discord Classic
//
//  Created by plx on 7/13/25.
//  Copyright (c) 2025 plzdonthaxme. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <UIKit/UIKit.h>

@interface DCGuildFolder : NSObject 

@property NSString *name;
@property int color;
@property int id;
@property NSArray *guildIds;
@property BOOL opened;
@property UIImage *icon;

@end