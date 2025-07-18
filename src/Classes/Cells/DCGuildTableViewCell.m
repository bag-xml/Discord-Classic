//
//  DCGuildTableViewCell.m
//  Discord Classic
//
//  Created by XML on 22/12/24.
//  Copyright (c) 2024 bag.xml. All rights reserved.
//

#import "DCGuildTableViewCell.h"

@implementation DCGuildTableViewCell

- (id)initWithStyle:(UITableViewCellStyle)style
    reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
    }
    return self;
}

- (void)awakeFromNib {
    // Initialization code
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
