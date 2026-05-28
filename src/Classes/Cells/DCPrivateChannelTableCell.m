//
//  DCPrivateChannelTableCell.m
//  Discord Classic
//
//  Created by XML on 28/12/24.
//  Copyright (c) 2024 bag.xml. All rights reserved.
//

#import "DCPrivateChannelTableCell.h"

@implementation DCPrivateChannelTableCell

- (void)awakeFromNib {
    [super awakeFromNib];
    self.mentionBadge = [MentionBadge badgeWithCount:0];
    [self.contentView addSubview:self.mentionBadge];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
}

@end
