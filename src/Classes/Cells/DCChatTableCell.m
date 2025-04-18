//
//  DCChatTableCell.m
//  Discord Classic
//
//  Created by bag.xml on 4/7/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import "DCChatTableCell.h"

@implementation DCChatTableCell

- (void)configureWithMessage:(NSString *)messageText {
    TSMarkdownParser *parser = [TSMarkdownParser standardParser];
    NSAttributedString *attributedText = [parser attributedStringFromMarkdown:messageText];
    if (attributedText) {
    } else {
    }
    
    self.contentTextView.attributedText = attributedText;
    [self adjustTextViewSize];
}


- (void)adjustTextViewSize {
    CGSize maxSize = CGSizeMake(self.contentTextView.frame.size.width, CGFLOAT_MAX);
    CGSize newSize = [self.contentTextView sizeThatFits:maxSize];
    
    CGRect newFrame = self.contentTextView.frame;
    newFrame.size.height = newSize.height;
    self.contentTextView.frame = newFrame;
}


@end