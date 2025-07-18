//
//  DCChatTableCell.h
//  Discord Classic
//
//  Created by bag.xml on 4/7/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "TSMarkdownParser.h"

@interface DCChatTableCell : UITableViewCell
@property (strong, nonatomic) IBOutlet UILabel *authorLabel;
@property (strong, nonatomic) IBOutlet UILabel *timestampLabel;
@property (weak, nonatomic) IBOutlet UIImageView *profileImage;
@property (weak, nonatomic) IBOutlet UIImageView *avatarDecoration;
@property (strong, nonatomic) IBOutlet UITextView *contentTextView;
@property (weak, nonatomic) IBOutlet UIImageView *referencedProfileImage;
@property (weak, nonatomic) IBOutlet UIImageView *universalImageView;
@property (strong, nonatomic) IBOutlet UILabel *referencedAuthorLabel;
@property (strong, nonatomic) IBOutlet UILabel *referencedMessage;

- (void)configureWithMessage:(NSString *)messageText;

@end
