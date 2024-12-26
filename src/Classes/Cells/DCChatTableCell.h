//
//  DCChatTableCell.h
//  Discord Classic
//
//  Created by Julian Triveri on 4/7/18.
//  Copyright (c) 2018 Julian Triveri. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DCChatTableCell : UITableViewCell
@property (strong, nonatomic) IBOutlet UILabel *authorLabel;
@property (strong, nonatomic) IBOutlet UILabel *timestampLabel;
@property (weak, nonatomic) IBOutlet UIImageView *profileImage;
@property (weak, nonatomic) IBOutlet UIImageView *avatarDecoration;
@property (strong, nonatomic) IBOutlet UITextView *contentTextView;
@property (weak, nonatomic) IBOutlet UIImageView *referencedProfileImage;
@property (strong, nonatomic) IBOutlet UILabel *referencedAuthorLabel;
@property (strong, nonatomic) IBOutlet UILabel *referencedMessage;
@end
