//
//  DCChatTableCell.m
//  Discord Classic
//
//  Created by bag.xml on 4/7/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import "DCChatTableCell.h"
#include "DCChatVideoAttachment.h"

@implementation DCChatTableCell

- (void)configureWithMessage:(NSString *)messageText {
    // @available doesn't exist on iOS 5, use respondsToSelector instead
    if ([self.contentTextView respondsToSelector:@selector(setAttributedText:)]) {
        static dispatch_once_t onceToken;
        static TSMarkdownParser *parser;
        dispatch_once(&onceToken, ^{
            parser = [TSMarkdownParser standardParser];
        });
        NSAttributedString *attributedText =
            [parser attributedStringFromMarkdown:messageText];
        if (attributedText) {
            self.contentTextView.attributedText = attributedText;
            [self adjustTextViewSize];
        }
    }
}


- (void)adjustTextViewSize {
    CGSize maxSize =
        CGSizeMake(self.contentTextView.frame.size.width, CGFLOAT_MAX);
    CGSize newSize = [self.contentTextView sizeThatFits:maxSize];

    CGRect newFrame            = self.contentTextView.frame;
    newFrame.size.height       = newSize.height;
    self.contentTextView.frame = newFrame;
}

@end