//
//  DCMarkdownParser.h
//  Discord Classic
//
//  Created by Ayeris on 5/23/26.
//  Copyright (c) 2026 Ayeris All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <UIKit/UIKit.h>

// Custom attribute key for block-level element type
// Value is an NSNumber wrapping a DCMarkdownBlockType enum value
extern NSString *const DCMarkdownBlockTypeAttributeName;

// Custom attribute key for spoiler ranges
// Value is the original plain text string of the spoiler content
extern NSString *const DCMarkdownSpoilerAttributeName;

typedef NS_ENUM(NSUInteger, DCMarkdownBlockType) {
    DCMarkdownBlockTypeCode,
    DCMarkdownBlockTypeBlockquote,
};

@interface DCMarkdownParser : NSObject

+ (instancetype)sharedParser;

// Primary parse method — returns CoreText-compatible attributed string
- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown;

// Inline fonts
@property (nonatomic, strong) UIFont *defaultFont;
@property (nonatomic, strong) UIFont *boldFont;
@property (nonatomic, strong) UIFont *italicFont;
@property (nonatomic, strong) UIFont *boldItalicFont;
@property (nonatomic, strong) UIFont *underlineFont;
@property (nonatomic, strong) UIFont *codeFont;

// Header and subtext fonts
@property (nonatomic, strong) UIFont *h1Font;
@property (nonatomic, strong) UIFont *h2Font;
@property (nonatomic, strong) UIFont *h3Font;
@property (nonatomic, strong) UIFont *subtextFont;

// Colors
@property (nonatomic, strong) UIColor *defaultColor;
@property (nonatomic, strong) UIColor *linkColor;
@property (nonatomic, strong) UIColor *mentionColor;
@property (nonatomic, strong) UIColor *codeTextColor;
@property (nonatomic, strong) UIColor *spoilerHiddenColor;
@property (nonatomic, strong) UIColor *blockquoteColor;
@property (nonatomic, strong) UIColor *subtextColor;
@property (nonatomic, strong) UIColor *strikethroughColor;

@end