//
//  DCChatTableCell.h
//  Discord Classic
//
//  Created by bag.xml on 4/7/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "TSMarkdownParser.h"
#import "DTAttributedLabel.h"

@interface DCChatTableCell : UITableViewCell
@property (strong, nonatomic) IBOutlet UILabel *authorLabel;
@property (strong, nonatomic) IBOutlet UILabel *timestampLabel;
@property (weak, nonatomic) IBOutlet UIImageView *profileImage;
@property (weak, nonatomic) IBOutlet UIImageView *avatarDecoration;
@property (strong, nonatomic) IBOutlet DTAttributedLabel *contentTextView;
@property (weak, nonatomic) IBOutlet UIImageView *referencedProfileImage;
@property (weak, nonatomic) IBOutlet UIImageView *universalImageView;
@property (strong, nonatomic) IBOutlet UILabel *referencedAuthorLabel;
@property (strong, nonatomic) IBOutlet DTAttributedLabel *referencedMessage;
@property (weak, nonatomic) IBOutlet UIImageView *separatorImageView;
@property (strong, nonatomic) NSString *messageSnowflake;
@property (strong, nonatomic) NSString *configuredSnowflake;
@property (nonatomic) CGFloat configuredWidth;

- (void)configureWithMessage:(NSString *)messageText;
- (void)adjustTextViewSize;

@end
