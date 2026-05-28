//
//  DCPrivateChannelTableCell.h
//  Discord Classic
//
//  Created by XML on 28/12/24.
//  Copyright (c) 2024 bag.xml. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MentionBadge.h"

@interface DCPrivateChannelTableCell : UITableViewCell
@property (weak, nonatomic) IBOutlet UIImageView *statusImage;
@property (weak, nonatomic) IBOutlet UILabel *nameLabel;
@property (weak, nonatomic) IBOutlet UIImageView *pfp;
@property (weak, nonatomic) IBOutlet UILabel *statusLabel;
@property (weak, nonatomic) IBOutlet UIImageView *unreadMessages;
@property (strong, nonatomic) MentionBadge *mentionBadge;
@end
