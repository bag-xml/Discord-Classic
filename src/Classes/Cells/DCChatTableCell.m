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

// - (void)configureWithMessage:(NSString *)messageText {
//     // @available doesn't exist on iOS 5, use respondsToSelector instead
//     if ([self.contentTextView respondsToSelector:@selector(setAttributedText:)]) {
//         static dispatch_once_t onceToken;
//         static TSMarkdownParser *parser;
//         dispatch_once(&onceToken, ^{
//             parser = [TSMarkdownParser standardParser];
//         });
//         NSAttributedString *attributedText =
//             [parser attributedStringFromMarkdown:messageText];
//         if (attributedText) {
//             self.contentTextView.attributedText = attributedText;
//             [self adjustTextViewSize];
//         }
//     }
// }


// - (void)adjustTextViewSize {
//     CGSize maxSize =
//         CGSizeMake(self.contentTextView.frame.size.width, CGFLOAT_MAX);
//     CGSize newSize = [self.contentTextView sizeThatFits:maxSize];

//     CGRect newFrame            = self.contentTextView.frame;
//     newFrame.size.height       = newSize.height;
//     self.contentTextView.frame = newFrame;
// }

// - (void)handleLabelTap:(UITapGestureRecognizer *)recognizer {
//     UILabel *label = (UILabel *)recognizer.view;
//     NSString *text = [label respondsToSelector:@selector(attributedText)] && label.attributedText
//         ? label.attributedText.string
//         : label.text;
//     if (!text.length) return;

//     CGPoint tapLocation = [recognizer locationInView:label];
//     UIFont *font = [UIFont systemFontOfSize:14];
//     float contentWidth = label.bounds.size.width;

//     NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
//     NSArray *matches = [detector matchesInString:text options:0 range:NSMakeRange(0, text.length)];

//     for (NSTextCheckingResult *match in matches) {
//         // Get text before the URL
//         NSString *textBeforeURL = [text substringToIndex:match.range.location];
//         NSString *urlText = [text substringWithRange:match.range];

//         // Measure where the URL starts
//         CGSize sizeBeforeURL = [textBeforeURL sizeWithFont:font
//                                          constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
//                                              lineBreakMode:NSLineBreakByWordWrapping];
//         CGSize urlSize = [urlText sizeWithFont:font
//                              constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
//                                  lineBreakMode:NSLineBreakByWordWrapping];

//         CGFloat urlY = sizeBeforeURL.height - font.lineHeight;
//         CGFloat urlEndY = urlY + urlSize.height;

//         if (tapLocation.y >= urlY && tapLocation.y <= urlEndY) {
//             [[UIApplication sharedApplication] openURL:match.URL];
//             return;
//         }
//     }
// }

- (void)awakeFromNib {
    [super awakeFromNib];
    // UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleLabelTap:)];
    // [self.contentTextView addGestureRecognizer:tap];
    // self.contentTextView.userInteractionEnabled = YES;
    
    self.profileImage.backgroundColor = [UIColor clearColor];
    self.profileImage.opaque = NO;
    self.referencedProfileImage.backgroundColor = [UIColor clearColor];
    self.referencedProfileImage.opaque = NO;
    self.referencedMessage.backgroundColor = [UIColor clearColor];
    
    self.contentTextView.frame = self.contentTextView.frame;
    self.contentTextView.backgroundColor = [UIColor clearColor];
    self.contentTextView.numberOfLines = 0;
    self.contentTextView.shouldDrawLinks = YES;
    self.contentTextView.userInteractionEnabled = YES;
    self.contentTextView.relayoutMask = DTAttributedTextContentViewRelayoutOnWidthChanged 
        | DTAttributedTextContentViewRelayoutOnHeightChanged;
}

@end