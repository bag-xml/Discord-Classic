//
//  DCGuildTableViewCell.h
//  Discord Classic
//
//  Created by XML on 22/12/24.
//  Copyright (c) 2024 bag.xml. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MentionBadge.h"

@interface DCGuildTableViewCell : UITableViewCell
@property (weak, nonatomic) IBOutlet UIImageView *guildAvatar;
@property (weak, nonatomic) IBOutlet UIImageView *unreadMessages;
@property (strong, nonatomic) MentionBadge *mentionBadge;
@end
