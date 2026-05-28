//
//  DCChatVideoAttachment.m
//  Discord Classic
//
//  Created by Toru the Red Fox on 25/10/22.
//  Copyright (c) 2022 Toru the Red Fox. All rights reserved.
//

#import "DCChatVideoAttachment.h"

@implementation DCChatVideoAttachment

- (void)awakeFromNib {
    [super awakeFromNib];
    self.videoWarning.hidden = YES;
    self.videoWarning.text = @"";
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.thumbnail.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
}

- (void)prepareForDisplay {
    self.thumbnail.frame = self.bounds;
    self.backgroundColor = self.thumbnail.image
        ? [UIColor clearColor]
        : [UIColor blackColor];
    self.videoWarning.frame = self.bounds;
    self.videoWarning.textAlignment = NSTextAlignmentCenter;
    [self bringSubviewToFront:self.playButton];
    [self bringSubviewToFront:self.videoWarning];
}

@end
