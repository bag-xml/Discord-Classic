//
//  TSMarkdownParser.m
//  TSMarkdownParser
//
//  Created by Tobias Sundstrand on 14-08-30.
//  Copyright (c) 2014 Computertalk Sweden. All rights reserved.
//

#import "TSMarkdownParser.h"
#import <UIKit/UIKit.h>

@interface TSExpressionBlockPair : NSObject

@property (nonatomic, strong) NSRegularExpression *regularExpression;
@property (nonatomic, strong) TSMarkdownParserMatchBlock block;

+ (TSExpressionBlockPair *)
    pairWithRegularExpression:(NSRegularExpression *)regularExpression
                        block:(TSMarkdownParserMatchBlock)block;

@end

@implementation TSExpressionBlockPair

+ (TSExpressionBlockPair *)
    pairWithRegularExpression:(NSRegularExpression *)regularExpression
                        block:(TSMarkdownParserMatchBlock)block {
    TSExpressionBlockPair *pair = [TSExpressionBlockPair new];
    pair.regularExpression      = regularExpression;
    pair.block                  = block;
    return pair;
}

@end

@interface TSMarkdownParser ()

@property (nonatomic, strong) NSMutableArray *parsingPairs;
@property (nonatomic, copy) void (^paragraphParsingBlock)
    (NSMutableAttributedString *attributedString);

@end

@implementation TSMarkdownParser

- (instancetype)init {
    self = [super init];
    if (self) {
        _parsingPairs       = [NSMutableArray array];
        _paragraphFont      = [UIFont systemFontOfSize:14];
        _strongFont         = [UIFont boldSystemFontOfSize:14];
        _emphasisFont       = [UIFont italicSystemFontOfSize:14];
        _h1Font             = [UIFont boldSystemFontOfSize:18];
        _h2Font             = [UIFont boldSystemFontOfSize:17];
        _h3Font             = [UIFont boldSystemFontOfSize:15];
        _h4Font             = [UIFont boldSystemFontOfSize:14];
        _h5Font             = [UIFont boldSystemFontOfSize:14];
        _h6Font             = [UIFont boldSystemFontOfSize:14];
        _linkColor          = [UIColor colorWithRed:74 / 255.0
                                     green:125 / 255.0
                                      blue:112 / 255.0
                                     alpha:1];
        _linkUnderlineStyle = @(NSUnderlineStyleSingle);
        // Menlo is unavailable on iOS 5~6, replace with Courier New
        _monospaceFont      = [UIFont fontWithName:@"Courier New" size:14];
        _monospaceTextColor = [UIColor colorWithRed:197 / 255.0
                                              green:135 / 255.0
                                               blue:10 / 255.0
                                              alpha:1];
    }
    return self;
}

+ (instancetype)standardParser {
    TSMarkdownParser *defaultParser = [TSMarkdownParser new];

    __weak TSMarkdownParser *weakParser = defaultParser;

    [defaultParser
        addParagraphParsingWithFormattingBlock:^(
            NSMutableAttributedString *attributedString, NSRange range
        ) {
            [attributedString addAttribute:NSFontAttributeName
                                     value:weakParser.paragraphFont
                                     range:range];
            [attributedString addAttribute:NSForegroundColorAttributeName
                                     value:[UIColor colorWithRed:230 / 255.0
                                                           green:230 / 255.0
                                                            blue:230 / 255.0
                                                           alpha:1]
                                     range:range];
        }];


    /* block parsing */

    [defaultParser
        addHeaderParsingWithLevel:1
                  formattingBlock:^(
                      NSMutableAttributedString *attributedString, NSRange range
                  ) {
                      [attributedString addAttribute:NSFontAttributeName
                                               value:weakParser.h1Font
                                               range:range];
                  }];

    [defaultParser
        addHeaderParsingWithLevel:2
                  formattingBlock:^(
                      NSMutableAttributedString *attributedString, NSRange range
                  ) {
                      [attributedString addAttribute:NSFontAttributeName
                                               value:weakParser.h2Font
                                               range:range];
                  }];

    [defaultParser
        addHeaderParsingWithLevel:3
                  formattingBlock:^(
                      NSMutableAttributedString *attributedString, NSRange range
                  ) {
                      [attributedString addAttribute:NSFontAttributeName
                                               value:weakParser.h3Font
                                               range:range];
                  }];

    [defaultParser
        addHeaderParsingWithLevel:4
                  formattingBlock:^(
                      NSMutableAttributedString *attributedString, NSRange range
                  ) {
                      [attributedString addAttribute:NSFontAttributeName
                                               value:weakParser.h4Font
                                               range:range];
                  }];

    [defaultParser
        addHeaderParsingWithLevel:5
                  formattingBlock:^(
                      NSMutableAttributedString *attributedString, NSRange range
                  ) {
                      [attributedString addAttribute:NSFontAttributeName
                                               value:weakParser.h5Font
                                               range:range];
                  }];

    [defaultParser
        addHeaderParsingWithLevel:6
                  formattingBlock:^(
                      NSMutableAttributedString *attributedString, NSRange range
                  ) {
                      [attributedString addAttribute:NSFontAttributeName
                                               value:weakParser.h6Font
                                               range:range];
                  }];

    [defaultParser
        addListParsingWithFormattingBlock:^(
            NSMutableAttributedString *attributedString, NSRange range
        ) {
            [attributedString replaceCharactersInRange:range withString:@"• "];
        }];

    /* bracket parsing */

    [defaultParser
        addImageParsingWithImageFormattingBlock:^(
            NSMutableAttributedString *attributedString, NSRange range
        ) {
            // no additional formatting
        }
                 alternativeTextFormattingBlock:^(
                     NSMutableAttributedString *attributedString, NSRange range
                 ){
                     // no additional formatting
                 }];

    [defaultParser
        addLinkParsingWithFormattingBlock:^(
            NSMutableAttributedString *attributedString, NSRange range
        ) {
            [attributedString addAttribute:NSUnderlineStyleAttributeName
                                     value:weakParser.linkUnderlineStyle
                                     range:range];
            [attributedString addAttribute:NSForegroundColorAttributeName
                                     value:weakParser.linkColor
                                     range:range];
        }];

    /* inline parsing */


    [defaultParser
        addStrongParsingWithFormattingBlock:^(
            NSMutableAttributedString *attributedString, NSRange range
        ) {
            [attributedString addAttribute:NSFontAttributeName
                                     value:weakParser.strongFont
                                     range:range];
        }];

    [defaultParser
        addEmphasisParsingWithFormattingBlock:^(
            NSMutableAttributedString *attributedString, NSRange range
        ) {
            [attributedString addAttribute:NSFontAttributeName
                                     value:weakParser.emphasisFont
                                     range:range];
        }];

    [defaultParser
        addMonospacedParsingWithFormattingBlock:^(
            NSMutableAttributedString *attributedString, NSRange range
        ) {
            [attributedString addAttribute:NSFontAttributeName
                                     value:weakParser.monospaceFont
                                     range:range];
        }];

    return defaultParser;
}

// block regex
static NSString *const TSMarkdownHeaderRegex = @"^(#{%i}\\s{1})(?!#).*$";
// Headers — not applicable in Discord; skipping

// Lists — keep simple bullets only, allow for whitespace after symbol
static NSString *const TSMarkdownListRegex = @"^(\\*|\\+|\\-)\\s+.+$";

// Images — Discord doesn't render images from Markdown, optional: match nothing
static NSString *const TSMarkdownImageRegex =
    @"\\!\\[.*?\\]\\(\\S*\\)"; // keep if needed for parsing but won't render

// Links — match [text](url), but Discord doesn't show them as links
static NSString *const TSMarkdownLinkRegex =
    @"(?<!\\!)\\[([^\\]]+)\\]\\(([^\\)]+)\\)";

// Inline code — Discord only uses single backticks for inline
static NSString *const TSMarkdownMonospaceRegex = @"`([^`\n]+)`";

// Bold — either **bold** or __bold__
static NSString *const TSMarkdownStrongRegex = @"(\\*\\*|__)(.*?)\\1";

// Italics — either *italic* or _italic_ (but not **bold**)
static NSString *const TSMarkdownEmRegex =
    @"(?<!\\*)\\*(?!\\*)(.*?)\\*|(?<!_)_(?!_)(.*?)_";


- (void)addParagraphParsingWithFormattingBlock:
    (void (^)(NSMutableAttributedString *attributedString, NSRange range)
    )formattingBlock {
    self.paragraphParsingBlock =
        ^(NSMutableAttributedString *attributedString) {
            formattingBlock(
                attributedString, NSMakeRange(0, attributedString.length)
            );
        };
}

#pragma mark block parsing

- (void)addHeaderParsingWithLevel:(int)header
                  formattingBlock:(TSMarkdownParserFormattingBlock
                                  )formattingBlock {
    NSString *headerRegex =
        [NSString stringWithFormat:TSMarkdownHeaderRegex, header];
    NSRegularExpression *headerExpression = [NSRegularExpression
        regularExpressionWithPattern:headerRegex
                             options:NSRegularExpressionCaseInsensitive
                             | NSRegularExpressionAnchorsMatchLines
                               error:nil];
    [self addParsingRuleWithRegularExpression:headerExpression
                                    withBlock:^(
                                        NSTextCheckingResult *match,
                                        NSMutableAttributedString
                                            *attributedString
                                    ) {
                                        formattingBlock(
                                            attributedString, match.range
                                        );
                                        [attributedString
                                            deleteCharactersInRange:
                                                [match rangeAtIndex:1]];
                                    }];
}

- (void)addListParsingWithFormattingBlock:(TSMarkdownParserFormattingBlock
                                          )formattingBlock {
    NSRegularExpression *listParsing = [NSRegularExpression
        regularExpressionWithPattern:TSMarkdownListRegex
                             options:NSRegularExpressionCaseInsensitive
                             | NSRegularExpressionAnchorsMatchLines
                               error:nil];
    [self addParsingRuleWithRegularExpression:listParsing
                                    withBlock:^(
                                        NSTextCheckingResult *match,
                                        NSMutableAttributedString
                                            *attributedString
                                    ) {
                                        formattingBlock(
                                            attributedString,
                                            NSMakeRange(match.range.location, 1)
                                        );
                                    }];
}

#pragma mark bracket parsing

- (void)addImageParsingWithImageFormattingBlock:(TSMarkdownParserFormattingBlock
                                                )formattingBlock
                 alternativeTextFormattingBlock:(TSMarkdownParserFormattingBlock
                                                )alternativeFormattingBlock {
    NSRegularExpression *headerExpression = [NSRegularExpression
        regularExpressionWithPattern:TSMarkdownImageRegex
                             options:NSRegularExpressionCaseInsensitive
                               error:nil];
    [self
        addParsingRuleWithRegularExpression:headerExpression
                                  withBlock:^(
                                      NSTextCheckingResult *match,
                                      NSMutableAttributedString
                                          *attributedString
                                  ) {
                                      NSUInteger imagePathStart =
                                          [attributedString.string
                                              rangeOfString:@"("
                                                    options:0
                                                      range:match.range]
                                              .location;
                                      NSRange linkRange = NSMakeRange(
                                          imagePathStart,
                                          match.range.length
                                              + match.range.location
                                              - imagePathStart - 1
                                      );
                                      NSString *imagePath =
                                          [attributedString.string
                                              substringWithRange:
                                                  NSMakeRange(
                                                      linkRange.location + 1,
                                                      linkRange.length - 1
                                                  )];
                                      UIImage *image =
                                          [UIImage imageNamed:imagePath];
                                      if (image) {
                                          [attributedString
                                              deleteCharactersInRange:
                                                  match.range];
                                          NSTextAttachment *imageAttachment =
                                              [NSTextAttachment new];
                                          imageAttachment.image  = image;
                                          imageAttachment.bounds = CGRectMake(
                                              0, -5, image.size.width,
                                              image.size.height
                                          );
                                          NSAttributedString *imgStr =
                                              [NSAttributedString
                                                  attributedStringWithAttachment:
                                                      imageAttachment];
                                          NSRange imageRange = NSMakeRange(
                                              match.range.location, 1
                                          );
                                          [attributedString
                                              insertAttributedString:imgStr
                                                             atIndex:
                                                                 match.range
                                                                     .location];
                                          if (formattingBlock) {
                                              formattingBlock(
                                                  attributedString, imageRange
                                              );
                                          }
                                      } else {
                                          NSUInteger linkTextEndLocation =
                                              [attributedString.string
                                                  rangeOfString:@"]"
                                                        options:0
                                                          range:match.range]
                                                  .location;
                                          NSRange linkTextRange = NSMakeRange(
                                              match.range.location + 2,
                                              linkTextEndLocation
                                                  - match.range.location - 2
                                          );
                                          NSString *alternativeText =
                                              [attributedString.string
                                                  substringWithRange:
                                                      linkTextRange];
                                          if (alternativeFormattingBlock) {
                                              alternativeFormattingBlock(
                                                  attributedString, match.range
                                              );
                                          }
                                          [attributedString
                                              replaceCharactersInRange:
                                                  match.range
                                                            withString:
                                                                alternativeText];
                                      }
                                  }];
}

- (void)addLinkParsingWithFormattingBlock:(TSMarkdownParserFormattingBlock
                                          )formattingBlock {
    NSRegularExpression *linkParsing = [NSRegularExpression
        regularExpressionWithPattern:TSMarkdownLinkRegex
                             options:NSRegularExpressionCaseInsensitive
                               error:nil];

    [self
        addParsingRuleWithRegularExpression:linkParsing
                                  withBlock:^(
                                      NSTextCheckingResult *match,
                                      NSMutableAttributedString
                                          *attributedString
                                  ) {
                                      NSUInteger linkStartInResult =
                                          [attributedString.string
                                              rangeOfString:@"("
                                                    options:NSBackwardsSearch
                                                      range:match.range]
                                              .location;
                                      NSRange linkRange = NSMakeRange(
                                          linkStartInResult,
                                          match.range.length
                                              + match.range.location
                                              - linkStartInResult - 1
                                      );
                                      NSString *linkURLString =
                                          [attributedString.string
                                              substringWithRange:
                                                  NSMakeRange(
                                                      linkRange.location + 1,
                                                      linkRange.length - 1
                                                  )];
                                      NSURL *url = [NSURL
                                          URLWithString:
                                              [linkURLString
                                                  stringByAddingPercentEscapesUsingEncoding:
                                                      NSUTF8StringEncoding]];

                                      NSUInteger linkTextEndLocation =
                                          [attributedString.string
                                              rangeOfString:@"]"
                                                    options:0
                                                      range:match.range]
                                              .location;
                                      NSRange linkTextRange = NSMakeRange(
                                          match.range.location,
                                          linkTextEndLocation
                                              - match.range.location - 1
                                      );

                                      [attributedString
                                          deleteCharactersInRange:
                                              NSMakeRange(
                                                  match.range.location, 1
                                              )];
                                      [attributedString
                                          deleteCharactersInRange:
                                              NSMakeRange(
                                                  linkRange.location - 2,
                                                  linkRange.length + 2
                                              )];

                                      if (url) {
                                          [attributedString
                                              addAttribute:NSLinkAttributeName
                                                     value:url
                                                     range:linkTextRange];
                                      }

                                      formattingBlock(
                                          attributedString, linkTextRange
                                      );
                                  }];
}

#pragma mark inline parsing

- (void)addMonospacedParsingWithFormattingBlock:(TSMarkdownParserFormattingBlock
                                                )formattingBlock {
    NSRegularExpression *monoParsing = [NSRegularExpression
        regularExpressionWithPattern:TSMarkdownMonospaceRegex
                             options:NSRegularExpressionCaseInsensitive
                               error:nil];
    [self
        addParsingRuleWithRegularExpression:monoParsing
                                  withBlock:^(NSTextCheckingResult *match, NSMutableAttributedString *attributedString) {
                                      formattingBlock(attributedString, match.range);
                                      [attributedString
                                          deleteCharactersInRange:NSMakeRange(match.range.location, 1)];
                                      [attributedString
                                          deleteCharactersInRange:NSMakeRange((match.range.location + match.range.length - 2), 1)];
                                  }];
}

- (void)addStrongParsingWithFormattingBlock:
    (void (^)(NSMutableAttributedString *attributedString, NSRange range)
    )formattingBlock {
    NSRegularExpression *boldParsing = [NSRegularExpression
        regularExpressionWithPattern:TSMarkdownStrongRegex
                             options:NSRegularExpressionCaseInsensitive
                               error:nil];

    [self
        addParsingRuleWithRegularExpression:boldParsing
                                  withBlock:^(
                                      NSTextCheckingResult *match,
                                      NSMutableAttributedString
                                          *attributedString
                                  ) {
                                      formattingBlock(
                                          attributedString, match.range
                                      );

                                      [attributedString
                                          deleteCharactersInRange:
                                              NSMakeRange(
                                                  match.range.location, 2
                                              )];
                                      [attributedString
                                          deleteCharactersInRange:
                                              NSMakeRange(
                                                  match.range.location
                                                      + match.range.length - 4,
                                                  2
                                              )];
                                  }];
}

- (void)addEmphasisParsingWithFormattingBlock:(TSMarkdownParserFormattingBlock
                                              )formattingBlock {
    NSRegularExpression *emphasisParsing = [NSRegularExpression
        regularExpressionWithPattern:TSMarkdownEmRegex
                             options:NSRegularExpressionCaseInsensitive
                               error:nil];

    [self
        addParsingRuleWithRegularExpression:emphasisParsing
                                  withBlock:^(
                                      NSTextCheckingResult *match,
                                      NSMutableAttributedString
                                          *attributedString
                                  ) {
                                      formattingBlock(
                                          attributedString, match.range
                                      );

                                      [attributedString
                                          deleteCharactersInRange:
                                              NSMakeRange(
                                                  match.range.location, 1
                                              )];
                                      [attributedString
                                          deleteCharactersInRange:
                                              NSMakeRange(
                                                  match.range.location
                                                      + match.range.length - 2,
                                                  1
                                              )];
                                  }];
}

#pragma mark -

- (void
)addParsingRuleWithRegularExpression:(NSRegularExpression *)regularExpression
                           withBlock:(TSMarkdownParserMatchBlock)block {
    @synchronized(self) {
        [self.parsingPairs
            addObject:[TSExpressionBlockPair
                          pairWithRegularExpression:regularExpression
                                              block:block]];
    }
}

- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown
                                          attributes:
                                              (NSDictionary *)attributes {
    NSAttributedString *attributedString = nil;
    if (!attributes) {
        attributedString = [[NSAttributedString alloc] initWithString:markdown];
    } else {
        attributedString =
            [[NSAttributedString alloc] initWithString:markdown
                                            attributes:attributes];
    }

    return [self attributedStringFromAttributedMarkdownString:attributedString];
}

- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown {
    return [self attributedStringFromMarkdown:markdown attributes:nil];
}

- (NSAttributedString *)attributedStringFromAttributedMarkdownString:
    (NSAttributedString *)attributedString {
    NSMutableAttributedString *mutableAttributedString =
        [[NSMutableAttributedString alloc]
            initWithAttributedString:attributedString];
    if (self.paragraphParsingBlock) {
        self.paragraphParsingBlock(mutableAttributedString);
    }

    @synchronized(self) {
        for (TSExpressionBlockPair *expressionBlockPair in self.parsingPairs) {
            NSTextCheckingResult *match;
            while ((
                match = [expressionBlockPair.regularExpression
                    firstMatchInString:mutableAttributedString.string
                               options:0
                                 range:NSMakeRange(
                                           0,
                                           mutableAttributedString.string.length
                                       )]
            )) {
                expressionBlockPair.block(match, mutableAttributedString);
            }
        }
    }
    return mutableAttributedString;
}

@end
