//
//  DCChatGifAttachment.h
//  Discord Classic
//
//  Created by Ayeris on 3/12/26.
//  Copyright (c) 2026 bag.xml. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DCChatGifAttachment : UIView
@property (weak, nonatomic) IBOutlet UIImageView *gifThumbnail;
@property (weak, nonatomic) IBOutlet UIImageView *gifBadge;
@property (strong, nonatomic) NSURL *gifURL;
@property (strong, nonatomic) UIImage *staticThumbnail;
@property (nonatomic) BOOL isLoading;
- (void)stopPlayback;
- (void)prepareForDisplay;
@end
