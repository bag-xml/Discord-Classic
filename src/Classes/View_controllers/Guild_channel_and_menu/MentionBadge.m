//
//  MentionBadge.m
//  Discord Classic
//
//  Created by Ayeris on 3/28/26.
//  Copyright (c) 2026 Ayeris All rights reserved.
//

#import "MentionBadge.h"

@implementation MentionBadge {
    UIImageView *_backgroundImageView;
    UILabel *_label;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Stretchable badge image — 9pt caps left/right, 0 top/bottom
        UIImage *badgeImage = [[UIImage imageNamed:@"Badge"] 
                                resizableImageWithCapInsets:UIEdgeInsetsMake(0, 9, 0, 9)];
        
        _backgroundImageView = [[UIImageView alloc] initWithImage:badgeImage];
        _backgroundImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_backgroundImageView];
        
        _label = [[UILabel alloc] init];
        _label.backgroundColor = [UIColor clearColor];
        _label.textColor = [UIColor whiteColor];
        _label.font = [UIFont boldSystemFontOfSize:14];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_label];
    }
    return self;
}

+ (MentionBadge *)badgeWithCount:(NSInteger)count {
    MentionBadge *badge = [[MentionBadge alloc] initWithFrame:CGRectZero];
    badge.mentionCount = count;
    // NSLog(@"[MentionBadge] count=%ld frame=%@", (long)count, NSStringFromCGRect(badge.frame));
    return badge;
}

- (void)setMentionCount:(NSInteger)mentionCount {
    _mentionCount = mentionCount;
    self.hidden = (mentionCount == 0);
    _label.text = mentionCount > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)mentionCount];
    [self sizeToFit];
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGSize textSize = [_label.text sizeWithFont:_label.font]; // iOS 5 compatible
    CGFloat width = MAX(textSize.width + 18, 26); // 9pt padding each side, min 26pt
    return CGSizeMake(width, 26);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _backgroundImageView.frame = self.bounds;
    _label.frame = self.bounds;
}

@end