//
//  MentionBadge.h
//  Discord Classic
//
//  Created by Ayeris on 3/28/26.
//  Copyright (c) 2026 Ayeris All rights reserved.
//

#import <UIKit/UIKit.h>

@interface MentionBadge : UIView

@property (nonatomic, assign) NSInteger mentionCount;

+ (MentionBadge *)badgeWithCount:(NSInteger)count;

@end