//
//  DCChannelViewCell.m
//  Discord Classic
//
//  Created by XML on 23/12/24.
//  Copyright (c) 2024 bag.xml. All rights reserved.
//

#import "DCChannelViewCell.h"

@implementation DCChannelViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    self.mentionBadge = [MentionBadge badgeWithCount:0];
    [self.contentView addSubview:self.mentionBadge];
}

@end
