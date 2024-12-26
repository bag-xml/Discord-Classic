//
//  DCGuildTableViewCell.h
//  Discord Classic
//
//  Created by XML on 22/12/24.
//  Copyright (c) 2024 Julian Triveri. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DCGuildTableViewCell : UITableViewCell
@property (weak, nonatomic) IBOutlet UIImageView *guildAvatar;
@property (weak, nonatomic) IBOutlet UIImageView *unreadMessages;

@end
