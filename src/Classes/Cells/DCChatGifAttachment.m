//
//  DCChatGifAttachment.m
//  Discord Classic
//
//  Created by Ayeris on 3/12/26.
//  Copyright (c) 2026 bag.xml. All rights reserved.
//

#import "DCChatGifAttachment.h"
#import <SDWebImage/UIImageView+WebCache.h>

@interface DCChatGifAttachment ()
@property (strong, nonatomic) UIView *dimOverlay;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;
@end

@implementation DCChatGifAttachment

- (void)awakeFromNib {
    [super awakeFromNib];
    
    // Dim overlay
    self.dimOverlay = [[UIView alloc] initWithFrame:self.bounds];
    self.dimOverlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4f];
    self.dimOverlay.hidden = YES;
    self.dimOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:self.dimOverlay];
    
    // Spinner
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.center = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
    self.spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.spinner.hidden = YES;
    [self addSubview:self.spinner];
    
    // Make sure badge is on top
    [self bringSubviewToFront:self.gifBadge];
    
    // Tap gesture
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
    self.userInteractionEnabled = YES;
    [self addGestureRecognizer:tap];
    
}

- (void)prepareForDisplay {
    self.dimOverlay.frame = self.bounds;
    self.spinner.center = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
    // ensure overlay and spinner remain on top
    [self bringSubviewToFront:self.dimOverlay];
	[self bringSubviewToFront:self.spinner];
	[self bringSubviewToFront:self.gifBadge];
}

- (void)handleTap {
    if (self.isLoading) return;
    if (self.gifThumbnail.image != self.staticThumbnail) {
        // Already playing, stop it
        [self stopPlayback];
        return;
    }
    
    self.isLoading = YES;
    self.dimOverlay.hidden = NO;
    self.spinner.hidden = NO;
    [self.spinner startAnimating];
    self.gifBadge.hidden = YES;
    
    [[SDWebImageManager sharedManager] downloadImageWithURL:self.gifURL
                                                    options:SDWebImageCacheMemoryOnly
                                                   progress:nil
                                                  completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isLoading = NO;
            self.dimOverlay.hidden = YES;
            self.spinner.hidden = YES;
            [self.spinner stopAnimating];
            
            if (image && finished) {
                self.gifThumbnail.image = image;
            } else {
                self.gifBadge.hidden = NO;
            }
        });
    }];
}

- (void)stopPlayback {
    self.gifThumbnail.image = self.staticThumbnail;
    self.dimOverlay.hidden = YES;
    self.spinner.hidden = YES;
    [self.spinner stopAnimating];
    self.gifBadge.hidden = NO;
    self.isLoading = NO;
}

@end
