//
//  DCChatVideoAttachment.h
//  Discord Classic
//
//  Created by Toru the Red Fox on 25/10/22.
//  Copyright (c) 2022 Toru the Red Fox. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DCChatVideoAttachment : UIView
@property (strong, nonatomic) IBOutlet UIImageView *playButton;
@property (weak, nonatomic) IBOutlet UIImageView *thumbnail;
@property (strong, nonatomic) NSURL *videoURL;
@property (weak, nonatomic) IBOutlet UILabel *videoWarning;
@property (nonatomic, strong) NSURL *linkURL;

- (void) prepareForDisplay;
@end
