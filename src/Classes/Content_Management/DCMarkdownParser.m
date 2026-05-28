//
//  DCMarkdownParser.m
//  Discord Classic
//
//  Created by Ayeris on 5/23/26.
//  Copyright (c) 2026 Ayeris All rights reserved.
//
//  Parses Discord markdown into CoreText-compatible NSAttributedStrings.
//  Safe for use on iOS 5+.
//

#import "DCMarkdownParser.h"
#import "DTCoreTextConstants.h"
#import "DCServerCommunicator.h"
#import "DCEmoji.h"
#import "DTImageTextAttachment.h"
#import <CoreText/CoreText.h>

// Constants defined here, declared extern in header
NSString *const DCMarkdownBlockTypeAttributeName = @"DCMarkdownBlockType";
NSString *const DCMarkdownSpoilerAttributeName   = @"DCMarkdownSpoiler";

// Internal spoiler URL scheme used with DTCoreText link delegate
static NSString *const kDCSpoilerScheme = @"discord-spoiler";

// Emoji Callbacks
static CGFloat DCEmojiGetAscent(void *refCon)  { return 14.0f; }
static CGFloat DCEmojiGetDescent(void *refCon) { return 4.0f;  }
static CGFloat DCEmojiGetWidth(void *refCon)   { return 20.0f; }


@implementation DCMarkdownParser

#pragma mark - Singleton

+ (instancetype)sharedParser {
    static DCMarkdownParser *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[DCMarkdownParser alloc] init];
    });
    return instance;
}

#pragma mark - Init

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupDefaults];
    }
    return self;
}

- (void)setupDefaults {
    _defaultFont    = [UIFont systemFontOfSize:14];
    _boldFont       = [UIFont boldSystemFontOfSize:14];
    _italicFont     = [UIFont italicSystemFontOfSize:14];
    _boldItalicFont = [UIFont fontWithName:@"Helvetica-BoldOblique" size:14];
    _codeFont       = [UIFont fontWithName:@"Courier" size:13];
    _underlineFont  = [UIFont systemFontOfSize:14];
    _h1Font         = [UIFont boldSystemFontOfSize:22];
    _h2Font         = [UIFont boldSystemFontOfSize:18];
    _h3Font         = [UIFont boldSystemFontOfSize:16];
    _subtextFont    = [UIFont systemFontOfSize:11];

    _defaultColor       = [UIColor colorWithRed:230/255.0f green:230/255.0f blue:230/255.0f alpha:1.0f];
    _linkColor          = [UIColor colorWithRed:148/255.0f green:197/255.0f blue:250/255.0f alpha:1.0f];
    _mentionColor       = [UIColor colorWithRed:150/255.0f  green:164/255.0f blue:244/255.0f alpha:1.0f];
    _codeTextColor      = [UIColor colorWithRed:186/255.0f green:186/255.0f blue:186/255.0f alpha:1.0f];
    _spoilerHiddenColor = [UIColor colorWithRed:80/255.0f  green:80/255.0f  blue:80/255.0f  alpha:1.0f];
    _blockquoteColor    = [UIColor colorWithRed:163/255.0f green:166/255.0f blue:170/255.0f alpha:1.0f];
    _subtextColor       = [UIColor colorWithRed:230/255.0f green:230/255.0f blue:230/255.0f alpha:1.0f];
    _strikethroughColor = _defaultColor;

    _minimumLineHeight = 18.0f;
}


#pragma mark - CTFont Helper

// UIFont is NOT toll-free bridged to CTFontRef.
// This helper creates a proper CTFontRef and transfers ownership to ARC
// so it can be safely stored in NSDictionary attribute values.
- (id)ctFontRef:(UIFont *)font {
    CTFontRef ctFont = CTFontCreateWithName((__bridge CFStringRef)font.fontName,
                                            font.pointSize, NULL);
    return CFBridgingRelease(ctFont);
}


#pragma mark - Attribute Helpers

// All attribute dictionaries use CoreText keys and CGColorRef for colors
// so they are safe on iOS 5 and consumed natively by DTAttributedLabel.

- (NSDictionary *)baseAttributes {
    CGFloat minLineHeight = _minimumLineHeight;
    CTParagraphStyleSetting settings[] = {
        { kCTParagraphStyleSpecifierMinimumLineHeight, sizeof(CGFloat), &minLineHeight }
    };
    CTParagraphStyleRef paraStyle = CTParagraphStyleCreate(settings, 1);
    
    NSDictionary *attrs = @{
        (NSString *)kCTFontAttributeName:            [self ctFontRef:_defaultFont],
        (NSString *)kCTForegroundColorAttributeName: (__bridge id)_defaultColor.CGColor,
        (NSString *)kCTParagraphStyleAttributeName:  (__bridge id)paraStyle
    };
    CFRelease(paraStyle);
    return attrs;
}

- (NSDictionary *)attributesForFont:(UIFont *)font color:(UIColor *)color {
    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    if (font)  attrs[(NSString *)kCTFontAttributeName]            = [self ctFontRef:font];
    if (color) attrs[(NSString *)kCTForegroundColorAttributeName] = (__bridge id)color.CGColor;
    return attrs;
}

- (void)addAttributes:(NSDictionary *)attributes
              toRange:(NSRange)range
             inString:(NSMutableAttributedString *)string {
    if (range.location == NSNotFound || range.length == 0) return;
    if (NSMaxRange(range) > string.length) return;
    [string addAttributes:attributes range:range];
}


#pragma mark - Protected Range Helpers

- (BOOL)location:(NSUInteger)loc isProtectedBy:(NSArray *)protectedRanges {
    for (NSValue *val in protectedRanges) {
        NSRange r = val.rangeValue;
        if (loc >= r.location && loc < NSMaxRange(r)) return YES;
    }
    return NO;
}

- (BOOL)range:(NSRange)range isProtectedBy:(NSArray *)protectedRanges {
    for (NSValue *val in protectedRanges) {
        NSRange r = val.rangeValue;
        if (range.location < NSMaxRange(r) && NSMaxRange(range) > r.location) return YES;
    }
    return NO;
}


#pragma mark - Main Entry Point

- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown {
    if (!markdown || markdown.length == 0) {
        return [[NSAttributedString alloc] initWithString:@""];
    }

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc]
        initWithString:markdown
            attributes:[self baseAttributes]];

    NSMutableArray *protectedRanges = [NSMutableArray array];

    // Order matters — code blocks first to protect their contents
    [self applyMultilineCodeBlocks:result protectedRanges:protectedRanges];
    [self applyBlockLevelFormatting:result protectedRanges:protectedRanges];
    [self applyInlineFormatting:result protectedRanges:protectedRanges];
    [self applyCustomEmojis:result protectedRanges:protectedRanges];
    [self applyMentions:result protectedRanges:protectedRanges];
    [self applyURLDetection:result protectedRanges:protectedRanges];

    [self stripSyntaxMarkers:result];
    [self applyEscapes:result protectedRanges:protectedRanges];
        
    return [result copy];
}

- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown
                                         maxFontSize:(CGFloat)maxFontSize
                                               color:(UIColor *)color {
    DCMarkdownParser *p = [[DCMarkdownParser alloc] init];

    // Cap every font variant at maxFontSize
    p.defaultFont    = [UIFont systemFontOfSize:maxFontSize];
    p.boldFont       = [UIFont boldSystemFontOfSize:maxFontSize];
    p.italicFont     = [UIFont italicSystemFontOfSize:maxFontSize];
    p.boldItalicFont = [UIFont fontWithName:@"Helvetica-BoldOblique" size:maxFontSize];
    p.codeFont       = [UIFont fontWithName:@"Courier" size:maxFontSize];
    p.underlineFont  = [UIFont systemFontOfSize:maxFontSize];
    p.h1Font         = [UIFont boldSystemFontOfSize:maxFontSize];
    p.h2Font         = [UIFont boldSystemFontOfSize:maxFontSize];
    p.h3Font         = [UIFont boldSystemFontOfSize:maxFontSize];
    p.subtextFont    = [UIFont systemFontOfSize:maxFontSize];

    // Override all color slots with the requested color
    p.defaultColor       = color;
    p.linkColor          = color;
    p.mentionColor       = color;
    p.codeTextColor      = color;
    p.spoilerHiddenColor = color;
    p.blockquoteColor    = color;
    p.subtextColor       = color;
    p.strikethroughColor = color;

    // Zero the minimum line height so CoreText uses natural 10pt metrics —
    // the reply label is only 16px tall and the default 18pt floor would
    // push text outside the frame, making the label appear blank.
    p.minimumLineHeight = 0.0f;

    NSMutableAttributedString *result = [[p attributedStringFromMarkdown:markdown] mutableCopy];

    NSDictionary *shadowDict = @{
        @"Offset": [NSValue valueWithCGSize:CGSizeMake(0, 1)],
        @"Blur":   @(0.0f),
        @"Color":  [UIColor blackColor]
    };
    [result addAttribute:DTShadowsAttribute
                   value:@[ shadowDict ]
                   range:NSMakeRange(0, result.length)];

    return [result copy];

    return [p attributedStringFromMarkdown:markdown];
}

- (void)stripSyntaxMarkers:(NSMutableAttributedString *)string {
    NSArray *patterns = @[
        @"(?<!\\\\)(\\*\\*\\*)(.+?)(\\*\\*\\*)",
        @"(?<!\\\\)(\\*\\*)(.+?)(\\*\\*)",
        @"(?<!\\\\)(__)(.+?)(__)",
        @"(?<!\\\\)(~~)(.+?)(~~)",
        @"(?<!\\\\)(?<!\\*)(\\*)(?!\\*).+?(?<!\\*)(\\*)(?!\\*)",
    ];
    
    for (NSString *pattern in patterns) {
        NSRegularExpression *regex = [NSRegularExpression
            regularExpressionWithPattern:pattern
                                 options:NSRegularExpressionDotMatchesLineSeparators
                                   error:nil];
        NSArray *matches = [regex matchesInString:string.string
                                          options:0
                                            range:NSMakeRange(0, string.string.length)];
        for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
            NSRange trailingRange = [match rangeAtIndex:match.numberOfRanges - 1];
            NSRange leadingRange  = [match rangeAtIndex:1];
            
            // Skip if leading marker is preceded by backslash
            if (leadingRange.location > 0 && 
                [string.string characterAtIndex:leadingRange.location - 1] == '\\') {
                continue;
            }
            
            if (NSMaxRange(trailingRange) <= string.length) {
                [string replaceCharactersInRange:trailingRange withString:@""];
            }
            if (leadingRange.location != NSNotFound && 
                NSMaxRange(leadingRange) <= string.length) {
                [string replaceCharactersInRange:leadingRange withString:@""];
            }
        }
    }
}


#pragma mark - Step 2: Multiline Code Blocks

- (void)applyMultilineCodeBlocks:(NSMutableAttributedString *)string
                  protectedRanges:(NSMutableArray *)protectedRanges {
    NSString *text = string.string;
    NSUInteger length = text.length;
    NSUInteger i = 0;
    NSMutableArray *rangesToStrip = [NSMutableArray array];

    while (i + 2 < length) {
        if ([text characterAtIndex:i]     == '`' &&
            [text characterAtIndex:i + 1] == '`' &&
            [text characterAtIndex:i + 2] == '`') {

            NSUInteger openTick = i;
            NSUInteger contentStart = i + 3;

            NSUInteger langEnd = contentStart;
            while (langEnd < length && [text characterAtIndex:langEnd] != '\n') {
                langEnd++;
            }
            if (langEnd < length) langEnd++;
            contentStart = langEnd;

            NSRange closeRange = [text rangeOfString:@"```"
                                             options:0
                                               range:NSMakeRange(contentStart, length - contentStart)];
            if (closeRange.location == NSNotFound) {
                closeRange = NSMakeRange(length, 0);
            }

            NSRange blockRange   = NSMakeRange(openTick, NSMaxRange(closeRange) - openTick);
            NSRange contentRange = NSMakeRange(contentStart, closeRange.location - contentStart);

            NSDictionary *codeAttrs = @{
                (NSString *)kCTFontAttributeName: [self ctFontRef:_codeFont],
                DCMarkdownBlockTypeAttributeName: @(DCMarkdownBlockTypeCode)
            };
            if (contentRange.length > 0 && NSMaxRange(contentRange) <= string.length) {
                [self applyBackgroundStyle:DCMarkdownBackgroundStyleCode
                                  toRange:contentRange
                                 inString:string
                            overrideColor:nil];
                [string addAttributes:codeAttrs range:contentRange];
            }

            [protectedRanges addObject:[NSValue valueWithRange:blockRange]];

            // Queue fence ranges for stripping after the loop
            if (closeRange.location != length) {
                [rangesToStrip addObject:[NSValue valueWithRange:closeRange]];
            }
            [rangesToStrip addObject:[NSValue valueWithRange:NSMakeRange(openTick, contentStart - openTick)]];

            i = NSMaxRange(closeRange) > 0 ? NSMaxRange(closeRange) : length;
        } else {
            i++;
        }
    }

    // Strip fence markers in reverse order to preserve positions
    NSArray *sorted = [rangesToStrip sortedArrayUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
        return a.rangeValue.location < b.rangeValue.location ? NSOrderedDescending : NSOrderedAscending;
    }];
    for (NSValue *val in sorted) {
        NSRange range = val.rangeValue;
        if (NSMaxRange(range) <= string.length) {
            [string replaceCharactersInRange:range withString:@""];
        }
    }
}


#pragma mark - Step 3: Block Level Formatting

- (void)applyBlockLevelFormatting:(NSMutableAttributedString *)string
                   protectedRanges:(NSMutableArray *)protectedRanges {
    NSString *text = string.string;
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    NSUInteger lineStart = 0;
    NSInteger cumulativeDelta = 0;

    for (NSString *line in lines) {
        NSUInteger lineLength = line.length;
        NSRange lineRange = NSMakeRange(lineStart + cumulativeDelta, lineLength);

        if (lineRange.location + lineLength > string.length) {
            lineStart += lineLength + 1;
            continue;
        }

        if (![self range:lineRange isProtectedBy:protectedRanges]) {
            NSUInteger lengthBefore = string.length;
            [self applyBlockFormattingToLine:line
                                       range:lineRange
                                    inString:string
                             protectedRanges:protectedRanges];
            NSInteger delta = (NSInteger)string.length - (NSInteger)lengthBefore;
            cumulativeDelta += delta;
        }
        lineStart += lineLength + 1;
    }
}

- (void)applyBlockFormattingToLine:(NSString *)line
                              range:(NSRange)lineRange
                           inString:(NSMutableAttributedString *)string
                    protectedRanges:(NSMutableArray *)protectedRanges {
    if (line.length == 0) return;

    if ([line hasPrefix:@"### "]) {
        [self addAttributes:[self attributesForFont:_h3Font color:_defaultColor]
                    toRange:lineRange inString:string];
        [string replaceCharactersInRange:NSMakeRange(lineRange.location, 4) withString:@""];
        return;
    }
    if ([line hasPrefix:@"## "]) {
        [self addAttributes:[self attributesForFont:_h2Font color:_defaultColor]
                    toRange:lineRange inString:string];
        [string replaceCharactersInRange:NSMakeRange(lineRange.location, 3) withString:@""];
        return;
    }
    if ([line hasPrefix:@"# "]) {
        [self addAttributes:[self attributesForFont:_h1Font color:_defaultColor]
                    toRange:lineRange inString:string];
        [string replaceCharactersInRange:NSMakeRange(lineRange.location, 2) withString:@""];
        return;
    }
    if ([line hasPrefix:@"-# "]) {
        [self addAttributes:[self attributesForFont:_subtextFont color:_subtextColor]
                    toRange:lineRange inString:string];
        [string replaceCharactersInRange:NSMakeRange(lineRange.location, 3) withString:@""];
        // Don't return — let inline formatting run on this line
    }
    if ([line hasPrefix:@">>> "] || [line hasPrefix:@"> "]) {
        NSUInteger prefixLength = [line hasPrefix:@">>> "] ? 4 : 2;
        NSRange prefixRange = NSMakeRange(lineRange.location, prefixLength);
        
        // Replace prefix with bar character + space
        [string replaceCharactersInRange:prefixRange withString:@"▎ "];
        
        // Adjust lineRange for the replacement
        NSInteger lengthDelta = 2 - (NSInteger)prefixLength;
        NSRange adjustedRange = NSMakeRange(lineRange.location, lineRange.length + lengthDelta);
        
        // Style the bar character with default color
        [string addAttribute:(NSString *)kCTForegroundColorAttributeName
                       value:(__bridge id)_defaultColor.CGColor
                       range:NSMakeRange(lineRange.location, 1)];
        
        // Style the text with blockquote color and indent
        CGFloat indent = 12.0f;
        CGFloat firstLine = 0.0f;
        CTParagraphStyleSetting settings[] = {
            { kCTParagraphStyleSpecifierHeadIndent,          sizeof(CGFloat), &indent },
            { kCTParagraphStyleSpecifierFirstLineHeadIndent, sizeof(CGFloat), &firstLine }
        };
        CTParagraphStyleRef paraStyle = CTParagraphStyleCreate(settings, 2);
        [string addAttribute:(NSString *)kCTParagraphStyleAttributeName
                       value:(__bridge id)paraStyle
                       range:adjustedRange];
        CFRelease(paraStyle);
        
        [string addAttribute:(NSString *)kCTForegroundColorAttributeName
                       value:(__bridge id)_blockquoteColor.CGColor
                       range:adjustedRange];
        
        [string addAttribute:DCMarkdownBlockTypeAttributeName
                       value:@(DCMarkdownBlockTypeBlockquote)
                       range:adjustedRange];

        // Check for subtext inside blockquote
        NSString *afterPrefix = [line substringFromIndex:prefixLength];
        if ([afterPrefix hasPrefix:@"-# "]) {
            NSRange subtextRange = NSMakeRange(lineRange.location + 2, adjustedRange.length - 2);
            [self addAttributes:[self attributesForFont:_subtextFont color:_subtextColor]
                        toRange:subtextRange inString:string];
            // Strip the -# marker
            NSRange markerRange = NSMakeRange(lineRange.location + 2, 3);
            if (NSMaxRange(markerRange) <= string.length) {
                [string replaceCharactersInRange:markerRange withString:@""];
            }
        }
    }

    if ([line hasPrefix:@"  - "] || [line hasPrefix:@"  * "]) {
        NSRange markerRange = NSMakeRange(lineRange.location + 2, 1);
        [string replaceCharactersInRange:markerRange withString:@"◦"];
        
        [string addAttribute:(NSString *)kCTFontAttributeName
                       value:[self ctFontRef:[UIFont systemFontOfSize:14]]
                       range:NSMakeRange(lineRange.location + 2, 1)];
        
        CGFloat hangIndent = 28.0f;
        CGFloat firstLine  = 0.0f;
        CTParagraphStyleSetting settings[] = {
            { kCTParagraphStyleSpecifierHeadIndent,          sizeof(CGFloat), &hangIndent },
            { kCTParagraphStyleSpecifierFirstLineHeadIndent, sizeof(CGFloat), &firstLine  }
        };
        CTParagraphStyleRef paraStyle = CTParagraphStyleCreate(settings, 2);
        [string addAttribute:(NSString *)kCTParagraphStyleAttributeName
                       value:(__bridge id)paraStyle
                       range:lineRange];
        CFRelease(paraStyle);
        return;
    }

    if ([line hasPrefix:@"- "] || [line hasPrefix:@"* "]) {
        NSRange markerRange = NSMakeRange(lineRange.location, 1);
        [string replaceCharactersInRange:markerRange withString:@"•"];
        
        [string addAttribute:(NSString *)kCTFontAttributeName
                       value:[self ctFontRef:[UIFont systemFontOfSize:15]]
                       range:NSMakeRange(lineRange.location, 1)];
        
        CGFloat hangIndent = 14.0f;
        CGFloat firstLine  = 0.0f;
        CTParagraphStyleSetting settings[] = {
            { kCTParagraphStyleSpecifierHeadIndent,          sizeof(CGFloat), &hangIndent },
            { kCTParagraphStyleSpecifierFirstLineHeadIndent, sizeof(CGFloat), &firstLine  },
        };
        CTParagraphStyleRef paraStyle = CTParagraphStyleCreate(settings, 2);
        [string addAttribute:(NSString *)kCTParagraphStyleAttributeName
                       value:(__bridge id)paraStyle
                       range:lineRange];
        CFRelease(paraStyle);
        return;
    }
}


#pragma mark - Step 4: Inline Formatting

- (void)applyInlineFormatting:(NSMutableAttributedString *)string
               protectedRanges:(NSMutableArray *)protectedRanges {
    [self applyMarkdownLinks:string protectedRanges:protectedRanges];
    [self applyInlineCode:string protectedRanges:protectedRanges];

    [self applyPattern:@"(?<!\\\\)\\*\\*\\*(.+?)\\*\\*\\*"
                  font:_boldItalicFont color:nil strikethrough:NO underline:NO
                string:string protectedRanges:protectedRanges];

    [self applyPattern:@"(?<!\\\\)\\*\\*(.+?)\\*\\*"
                  font:_boldFont color:nil strikethrough:NO underline:NO
                string:string protectedRanges:protectedRanges];

    [self applyPattern:@"(?<!\\\\)__(.+?)__"
                  font:_underlineFont color:nil strikethrough:NO underline:YES
                string:string protectedRanges:protectedRanges];

    [self applyPattern:@"(?<!\\*)(?<!\\\\)\\*(?!\\*)(.*?)(?<!\\*)\\*(?!\\*)|(?<!_)_(?!_)(.*?)_"
                  font:_italicFont color:nil strikethrough:NO underline:NO
                string:string protectedRanges:protectedRanges];

    [self applyPattern:@"(?<![a-zA-Z0-9])(?<!\\\\)_(.+?)_(?![a-zA-Z0-9])"
                  font:_italicFont color:nil strikethrough:NO underline:NO
                string:string protectedRanges:protectedRanges];

    [self applyPattern:@"(?<!\\\\)~~(.+?)~~"
                  font:nil color:_strikethroughColor strikethrough:YES underline:NO
                string:string protectedRanges:protectedRanges];

    [self applySpoilers:string protectedRanges:protectedRanges];
}

- (void)applyEscapes:(NSMutableAttributedString *)string
      protectedRanges:(NSMutableArray *)protectedRanges {
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"\\\\([*_~`|\\\\#])"
                             options:0
                               error:nil];
    
    NSArray *matches = [regex matchesInString:string.string
                                      options:0
                                        range:NSMakeRange(0, string.string.length)];
    
    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        // Remove the backslash, leaving just the escaped character
        NSRange backslashRange = NSMakeRange(match.range.location, 1);
        [string replaceCharactersInRange:backslashRange withString:@""];
        
        // Protect the now-exposed character from inline formatting
        NSRange charRange = NSMakeRange(match.range.location, 1);
        [protectedRanges addObject:[NSValue valueWithRange:charRange]];
    }
}

- (void)applyInlineCode:(NSMutableAttributedString *)string
         protectedRanges:(NSMutableArray *)protectedRanges {
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"`([^`\\n]+)`"
                             options:0
                               error:nil];

    NSArray *matches = [regex matchesInString:string.string
                                      options:0
                                        range:NSMakeRange(0, string.string.length)];
    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        if ([self range:match.range isProtectedBy:protectedRanges]) continue;

        NSDictionary *codeAttrs = @{
            (NSString *)kCTFontAttributeName: [self ctFontRef:_codeFont]
        };
        [self applyBackgroundStyle:DCMarkdownBackgroundStyleCode
                          toRange:match.range
                         inString:string
                    overrideColor:nil];
        [string addAttributes:codeAttrs range:match.range];

        // Strip markers — trailing first to preserve leading position
        NSRange trailingTick = NSMakeRange(NSMaxRange(match.range) - 1, 1);
        [string replaceCharactersInRange:trailingTick withString:@""];
        NSRange leadingTick = NSMakeRange(match.range.location, 1);
        [string replaceCharactersInRange:leadingTick withString:@""];

        NSRange strippedRange = NSMakeRange(match.range.location, match.range.length - 2);
        [protectedRanges addObject:[NSValue valueWithRange:strippedRange]];
    }
}

- (void)applyPattern:(NSString *)pattern
                font:(id)font
               color:(UIColor *)color
       strikethrough:(BOOL)strikethrough
           underline:(BOOL)underline
              string:(NSMutableAttributedString *)string
     protectedRanges:(NSMutableArray *)protectedRanges {
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:pattern
                             options:NSRegularExpressionDotMatchesLineSeparators
                               error:nil];
    NSArray *matches = [regex matchesInString:string.string
                                      options:0
                                        range:NSMakeRange(0, string.string.length)];
    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        if ([self range:match.range isProtectedBy:protectedRanges]) continue;
        NSRange contentRange = [match rangeAtIndex:1];
        if (contentRange.location == NSNotFound) {
            contentRange = [match rangeAtIndex:2];
        }
        if (contentRange.location == NSNotFound) continue;
        NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
        if (font) {
            attrs[(NSString *)kCTFontAttributeName] = [self ctFontRef:(UIFont *)font];
        }
        if (color) attrs[(NSString *)kCTForegroundColorAttributeName] = (__bridge id)color.CGColor;
        if (underline) attrs[(NSString *)kCTUnderlineStyleAttributeName] = @(kCTUnderlineStyleSingle);
        if (strikethrough) attrs[DTStrikeOutAttribute] = @YES;
        [string addAttributes:attrs range:match.range];
        [protectedRanges addObject:[NSValue valueWithRange:match.range]];
    }
}

- (void)applySpoilers:(NSMutableAttributedString *)string
       protectedRanges:(NSMutableArray *)protectedRanges {
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"\\|\\|(.+?)\\|\\|"
                             options:NSRegularExpressionDotMatchesLineSeparators
                               error:nil];

    NSArray *matches = [regex matchesInString:string.string
                                      options:0
                                        range:NSMakeRange(0, string.string.length)];

    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        if ([self range:match.range isProtectedBy:protectedRanges]) continue;

        NSRange innerRange = [match rangeAtIndex:1];
        NSString *innerText = [string.string substringWithRange:innerRange];

        // Strip the || markers, leave just the inner text
        [string replaceCharactersInRange:match.range withString:innerText];
        NSRange spoilerRange = NSMakeRange(match.range.location, innerText.length);

        NSString *encoded = [innerText stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSString *urlString = [NSString stringWithFormat:@"%@://%@", kDCSpoilerScheme, encoded];
        NSURL *spoilerURL = [NSURL URLWithString:urlString];

        [self applyBackgroundStyle:DCMarkdownBackgroundStyleSpoilerHidden
                          toRange:spoilerRange
                         inString:string
                    overrideColor:nil];
        [string addAttribute:DTLinkAttribute
                       value:spoilerURL ?: [NSNull null]
                       range:spoilerRange];
        [string addAttribute:DCMarkdownSpoilerAttributeName
                       value:innerText
                       range:spoilerRange];
        [protectedRanges addObject:[NSValue valueWithRange:spoilerRange]];
    }
}

- (void)applyMarkdownLinks:(NSMutableAttributedString *)string
            protectedRanges:(NSMutableArray *)protectedRanges {
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"\\[([^\\]]+)\\]\\(([^\\)]+)\\)"
                             options:0
                               error:nil];

    NSArray *matches = [regex matchesInString:string.string
                                      options:0
                                        range:NSMakeRange(0, string.string.length)];

    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        if ([self range:match.range isProtectedBy:protectedRanges]) continue;

        NSRange textRange = [match rangeAtIndex:1];
        NSRange urlRange  = [match rangeAtIndex:2];
        NSString *urlString = [string.string substringWithRange:urlRange];

        // Strip angle brackets
        if ([urlString hasPrefix:@"<"] && [urlString hasSuffix:@">"]) {
            urlString = [urlString substringWithRange:NSMakeRange(1, urlString.length - 2)];
        }

        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) continue;

        // Capture existing font before replacement
        id existingFont = [string attribute:(NSString *)kCTFontAttributeName
                                    atIndex:match.range.location
                             effectiveRange:NULL];

        CTFontRef existing = (__bridge CTFontRef)existingFont;
        CGFloat existingSize = existing ? CTFontGetSize(existing) : 14.0f;

        NSString *linkText = [string.string substringWithRange:textRange];
        [string replaceCharactersInRange:match.range withString:linkText];
        NSRange linkRange = NSMakeRange(match.range.location, linkText.length);

        NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
        attrs[(NSString *)kCTForegroundColorAttributeName] = (__bridge id)_linkColor.CGColor;
        UIFont *boldAtSize = [UIFont boldSystemFontOfSize:existingSize];
        attrs[(NSString *)kCTFontAttributeName] = [self ctFontRef:boldAtSize];
        attrs[DTLinkAttribute] = url;

        [string addAttributes:attrs range:linkRange];
        [protectedRanges addObject:[NSValue valueWithRange:linkRange]];
    }
}

- (void)applyBackgroundStyle:(DCMarkdownBackgroundStyle)style
                     toRange:(NSRange)range
                    inString:(NSMutableAttributedString *)string
               overrideColor:(UIColor *)overrideColor {
    if (range.location == NSNotFound || range.length == 0) return;
    if (NSMaxRange(range) > string.length) return;

    UIColor *backgroundColor = nil;
    UIColor *foregroundColor = nil;
    CGFloat cornerRadius = 3.0f;

    switch (style) {
        case DCMarkdownBackgroundStyleTag:
            backgroundColor = overrideColor 
                ?: [UIColor colorWithRed:88/255.0f green:101/255.0f blue:242/255.0f alpha:0.3f];
            foregroundColor = overrideColor
                ?: _mentionColor;
            break;

        case DCMarkdownBackgroundStyleTimestamp:
            backgroundColor = [UIColor colorWithRed:60/255.0f green:62/255.0f blue:68/255.0f alpha:1.0f];
            foregroundColor = [UIColor colorWithRed:180/255.0f green:182/255.0f blue:188/255.0f alpha:1.0f];
            break;

        case DCMarkdownBackgroundStyleCode:
            backgroundColor = [UIColor colorWithRed:30/255.0f green:31/255.0f blue:34/255.0f alpha:1.0f];
            foregroundColor = _codeTextColor;
            break;

        case DCMarkdownBackgroundStyleSpoilerHidden:
            backgroundColor = [UIColor colorWithRed:30/255.0f green:31/255.0f blue:34/255.0f alpha:1.0f];
            foregroundColor = [UIColor colorWithRed:30/255.0f green:31/255.0f blue:34/255.0f alpha:1.0f];
            break;

        case DCMarkdownBackgroundStyleSpoilerRevealed:
            backgroundColor = [UIColor colorWithRed:60/255.0f green:62/255.0f blue:68/255.0f alpha:1.0f];
            foregroundColor = _defaultColor;
            break;
    }

    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    
    if (backgroundColor) {
        attrs[DTBackgroundColorAttribute] = 
            (__bridge id)backgroundColor.CGColor;
        attrs[DTBackgroundCornerRadiusAttribute] = @(cornerRadius);
    }
    if (foregroundColor) {
        attrs[(NSString *)kCTForegroundColorAttributeName] = 
            (__bridge id)foregroundColor.CGColor;
    }

    [string addAttributes:attrs range:range];
}


#pragma mark - Step 5: Mentions and Timestamps

- (void)applyMentions:(NSMutableAttributedString *)string
       protectedRanges:(NSMutableArray *)protectedRanges {
    [self applyMentionPattern:@"<@!?([0-9]+)>"
                    urlPrefix:@"discord-user://"
                       string:string protectedRanges:protectedRanges];

    [self applyMentionPattern:@"<#([0-9]+)>"
                    urlPrefix:@"discord-channel://"
                       string:string protectedRanges:protectedRanges];

    [self applyMentionPattern:@"<@&([0-9]+)>"
                    urlPrefix:@"discord-role://"
                       string:string protectedRanges:protectedRanges];

    [self protectPattern:@"<:[a-zA-Z0-9_]+:[0-9]+>"
                  string:string protectedRanges:protectedRanges];

    [self applyLiteralMention:@"@everyone" string:string protectedRanges:protectedRanges];
    [self applyLiteralMention:@"@here"     string:string protectedRanges:protectedRanges];

    [self applyTimestamps:string protectedRanges:protectedRanges];
}

- (void)applyMentionPattern:(NSString *)pattern
                  urlPrefix:(NSString *)urlPrefix
                     string:(NSMutableAttributedString *)string
             protectedRanges:(NSMutableArray *)protectedRanges {
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:pattern
                             options:0
                               error:nil];

    NSArray *matches = [regex matchesInString:string.string
                                      options:0
                                        range:NSMakeRange(0, string.string.length)];

    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        if ([self range:match.range isProtectedBy:protectedRanges]) continue;

        NSRange idRange = [match rangeAtIndex:1];
        NSString *entityID = [string.string substringWithRange:idRange];

        // Look up display name
        NSString *displayText = nil;
        if ([urlPrefix isEqualToString:@"discord-user://"]) {
            DCUser *user = [DCServerCommunicator.sharedInstance userForSnowflake:entityID];
            displayText = user ? [NSString stringWithFormat:@"@%@", user.username] : @"@unknown";
        } else if ([urlPrefix isEqualToString:@"discord-channel://"]) {
            DCChannel *channel = [DCServerCommunicator.sharedInstance.channels objectForKey:entityID];
            displayText = channel ? [NSString stringWithFormat:@"#%@", channel.name] : @"#unknown";
        } else if ([urlPrefix isEqualToString:@"discord-role://"]) {
            DCRole *role = [DCServerCommunicator.sharedInstance roleForSnowflake:entityID];
            displayText = role ? [NSString stringWithFormat:@"@%@", role.name] : @"@role";
        } else if ([urlPrefix isEqualToString:@"discord-channel://"]) {
            DCChannel *channel = [DCServerCommunicator.sharedInstance.channels objectForKey:entityID];
            if (channel) {
                DCGuild *contextGuild = DCServerCommunicator.sharedInstance.selectedChannel.parentGuild;
                if (channel.parentGuild && 
                    channel.parentGuild != contextGuild) {
                    displayText = [NSString stringWithFormat:@"%@ > #%@", 
                        channel.parentGuild.name, channel.name];
                } else {
                    displayText = [NSString stringWithFormat:@"#%@", channel.name];
                }
            } else {
                displayText = @"#unknown";
            }
        }

        if (displayText) {
            [string replaceCharactersInRange:match.range withString:displayText];
        }
        NSRange replacedRange = NSMakeRange(match.range.location, displayText.length);

        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", urlPrefix, entityID]];

        [self applyBackgroundStyle:DCMarkdownBackgroundStyleTag
                          toRange:replacedRange
                         inString:string
                    overrideColor:nil];
        [string addAttribute:(NSString *)kCTFontAttributeName
                       value:[self ctFontRef:_boldFont]
                       range:replacedRange];
        [string addAttribute:DTLinkAttribute
                       value:url ?: [NSNull null]
                       range:replacedRange];
        [protectedRanges addObject:[NSValue valueWithRange:replacedRange]];
    }
}

- (void)applyLiteralMention:(NSString *)literal
                     string:(NSMutableAttributedString *)string
             protectedRanges:(NSMutableArray *)protectedRanges {
    NSString *text = string.string;
    NSRange searchRange = NSMakeRange(0, text.length);
    NSRange found;

    while ((found = [text rangeOfString:literal options:0 range:searchRange]).location != NSNotFound) {
        if (![self range:found isProtectedBy:protectedRanges]) {
            [self applyBackgroundStyle:DCMarkdownBackgroundStyleTag
                              toRange:found
                             inString:string
                        overrideColor:nil];
            [string addAttribute:(NSString *)kCTFontAttributeName
                           value:[self ctFontRef:_boldFont]
                           range:found];
            [protectedRanges addObject:[NSValue valueWithRange:found]];
        }
        searchRange.location = NSMaxRange(found);
        searchRange.length = text.length - searchRange.location;
    }
}

- (void)applyTimestamps:(NSMutableAttributedString *)string
         protectedRanges:(NSMutableArray *)protectedRanges {
    NSError *regexError = nil;
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"<t:([0-9]+)(?::([tTdDfFR]))?>"
                             options:0
                               error:&regexError];
    // NSLog(@"regex: %@ error: %@", regex, regexError);

    NSArray *matches = [regex matchesInString:string.string
                                      options:0
                                        range:NSMakeRange(0, string.string.length)];
    // NSLog(@"timestamp matches: %lu", (unsigned long)matches.count);

    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        if ([self range:match.range isProtectedBy:protectedRanges]) continue;

        NSRange tsRange    = [match rangeAtIndex:1];
        NSRange styleRange = [match rangeAtIndex:2];

        NSString *unixString = [string.string substringWithRange:tsRange];
        NSTimeInterval ts = [unixString doubleValue];
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];

        NSString *style = (styleRange.location != NSNotFound)
            ? [string.string substringWithRange:styleRange]
            : @"f";

        NSString *formatted = [self formattedTimestamp:date style:style];

        [string replaceCharactersInRange:match.range withString:formatted];
        NSRange replacedRange = NSMakeRange(match.range.location, formatted.length);

        [self applyBackgroundStyle:DCMarkdownBackgroundStyleTimestamp
                          toRange:replacedRange
                         inString:string
                    overrideColor:nil];
        // NSLog(@"timestamp attrs: %@", [string attributesAtIndex:replacedRange.location effectiveRange:NULL]);
        [protectedRanges addObject:[NSValue valueWithRange:replacedRange]];
    }
}

- (NSString *)formattedTimestamp:(NSDate *)date style:(NSString *)style {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];

    if ([style isEqualToString:@"t"]) {
        fmt.timeStyle = NSDateFormatterShortStyle;
        fmt.dateStyle = NSDateFormatterNoStyle;
    } else if ([style isEqualToString:@"T"]) {
        fmt.timeStyle = NSDateFormatterMediumStyle;
        fmt.dateStyle = NSDateFormatterNoStyle;
    } else if ([style isEqualToString:@"d"]) {
        fmt.timeStyle = NSDateFormatterNoStyle;
        fmt.dateStyle = NSDateFormatterShortStyle;
    } else if ([style isEqualToString:@"D"]) {
        fmt.timeStyle = NSDateFormatterNoStyle;
        fmt.dateStyle = NSDateFormatterLongStyle;
    } else if ([style isEqualToString:@"F"]) {
        fmt.timeStyle = NSDateFormatterShortStyle;
        fmt.dateStyle = NSDateFormatterFullStyle;
    } else if ([style isEqualToString:@"R"]) {
        NSTimeInterval delta = [[NSDate date] timeIntervalSinceDate:date];
        if (fabs(delta) < 60)       return @"just now";
        if (fabs(delta) < 3600)     return [NSString stringWithFormat:@"%d minutes ago", (int)round(delta / 60)];
        if (fabs(delta) < 86400)    return [NSString stringWithFormat:@"%d hours ago",   (int)round(delta / 3600)];
        if (fabs(delta) < 2592000)  return [NSString stringWithFormat:@"%d days ago",    (int)round(delta / 86400)];
        if (fabs(delta) < 31536000) return [NSString stringWithFormat:@"%d months ago",  (int)round(delta / 2592000)];
        return [NSString stringWithFormat:@"%d years ago", (int)round(delta / 31536000)];
    } else {
        fmt.timeStyle = NSDateFormatterShortStyle;
        fmt.dateStyle = NSDateFormatterLongStyle;
    }

    return [fmt stringFromDate:date];
}


#pragma mark - Step 6: Bare URL Detection

- (void)applyURLDetection:(NSMutableAttributedString *)string
           protectedRanges:(NSMutableArray *)protectedRanges {
    NSError *error = nil;
    NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink
                                                               error:&error];
    if (!detector) return;

    NSArray *matches = [detector matchesInString:string.string
                                         options:0
                                           range:NSMakeRange(0, string.string.length)];

    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        if ([self range:match.range isProtectedBy:protectedRanges]) continue;
        
        // Skip URLs wrapped in angle brackets — these belong to markdown links
        NSUInteger loc = match.range.location;
        if (loc > 0 && [string.string characterAtIndex:loc - 1] == '<') continue;
        
        NSURL *url = match.URL;
        if (!url) {
            NSString *urlString = [string.string substringWithRange:match.range];
            url = [NSURL URLWithString:urlString];
        }
        if (!url) continue;

        // Check for Discord channel deep link
        NSString *displayText = nil;
        if ([[url host] isEqualToString:@"discord.com"] &&
            [[url path] hasPrefix:@"/channels/"]) {
            NSArray *components = [url.path componentsSeparatedByString:@"/"];
            
            if (components.count >= 4) {
                // Channel link — existing handling
                NSString *channelId = components[3];
                DCChannel *channel = [DCServerCommunicator.sharedInstance.channels 
                    objectForKey:channelId];
                if (channel) {
                    if (channel.parentGuild &&
                        channel.parentGuild != DCServerCommunicator.sharedInstance.selectedChannel.parentGuild) {
                        displayText = [NSString stringWithFormat:@"%@ > #%@",
                            channel.parentGuild.name, channel.name];
                    } else {
                        displayText = [NSString stringWithFormat:@"#%@", channel.name];
                    }
                }
            } else if (components.count == 3) {
                // Guild-only link
                NSString *guildId = components[2];
                DCGuild *guild = nil;
                for (DCGuild *g in DCServerCommunicator.sharedInstance.guilds) {
                    if ([g.snowflake isEqualToString:guildId]) {
                        guild = g;
                        break;
                    }
                }
                if (guild) {
                    displayText = [NSString stringWithFormat:@"🏠 %@", guild.name];
                }
            }
        }

        if (displayText) {
            [string replaceCharactersInRange:match.range withString:displayText];
            NSRange replacedRange = NSMakeRange(match.range.location, displayText.length);
            [self applyBackgroundStyle:DCMarkdownBackgroundStyleTag
                              toRange:replacedRange
                             inString:string
                        overrideColor:nil];
            [string addAttribute:(NSString *)kCTFontAttributeName
                           value:[self ctFontRef:_boldFont]
                           range:replacedRange];
            [string addAttribute:DTLinkAttribute
                           value:url
                           range:replacedRange];
        } else {
            NSDictionary *attrs = @{
                (NSString *)kCTForegroundColorAttributeName: (__bridge id)_linkColor.CGColor,
                (NSString *)kCTFontAttributeName:            [self ctFontRef:_boldFont],
                DTLinkAttribute:                             url
            };
            [string addAttributes:attrs range:match.range];
        }
    }
}

#pragma mark - Custom Emoji Attachments

- (void)applyCustomEmojis:(NSMutableAttributedString *)string
           protectedRanges:(NSMutableArray *)protectedRanges {
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"<(a?):(\\w+):(\\d+)>"
                             options:0
                               error:nil];

    NSArray *matches = [regex matchesInString:string.string
                                      options:0
                                        range:NSMakeRange(0, string.string.length)];

    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        if ([self range:match.range isProtectedBy:protectedRanges]) continue;

        NSString *emojiID   = [string.string substringWithRange:[match rangeAtIndex:3]];
        NSString *emojiName = [string.string substringWithRange:[match rangeAtIndex:2]];
        DCEmoji *emoji      = [DCServerCommunicator.sharedInstance emojiForSnowflake:emojiID];

        if (!emoji) {
            // Token from a guild the client hasn't loaded — degrade gracefully
            NSString *fallback = [NSString stringWithFormat:@":%@:", emojiName];
            [string replaceCharactersInRange:match.range withString:fallback];
            [protectedRanges addObject:[NSValue valueWithRange:
                NSMakeRange(match.range.location, fallback.length)]];
            continue;
        }

        // Build the inline attachment. Image may be nil if the fetch hasn't
        // completed yet — the view will be empty until EMOJI IMAGE READY fires
        // and attributedContent is invalidated and rebuilt.
        DTImageTextAttachment *attachment = [[DTImageTextAttachment alloc] init];
        attachment.displaySize = CGSizeMake(18.0f, 18.0f);
        attachment.contentURL = [NSURL URLWithString:
            [NSString stringWithFormat:@"discord-emoji://%@", emojiID]];

        // CTRunDelegate tells CoreText to reserve the correct inline space
        CTRunDelegateCallbacks callbacks;
        memset(&callbacks, 0, sizeof(callbacks));
        callbacks.version    = kCTRunDelegateVersion1;
        callbacks.getAscent  = DCEmojiGetAscent;
        callbacks.getDescent = DCEmojiGetDescent;
        callbacks.getWidth   = DCEmojiGetWidth;
        CTRunDelegateRef runDelegate = CTRunDelegateCreate(&callbacks, NULL);

        // Replace the token with the Unicode attachment placeholder
        [string replaceCharactersInRange:match.range withString:@"\uFFFC"];
        NSRange attachRange = NSMakeRange(match.range.location, 1);

        [string addAttributes:@{
            NSAttachmentAttributeName:                   attachment,
            (NSString *)kCTRunDelegateAttributeName:     CFBridgingRelease(runDelegate),
            (NSString *)kCTForegroundColorAttributeName: (__bridge id)[UIColor clearColor].CGColor
        } range:attachRange];

        [protectedRanges addObject:[NSValue valueWithRange:attachRange]];
    }
}


#pragma mark - Utility

- (void)protectPattern:(NSString *)pattern
                string:(NSMutableAttributedString *)string
        protectedRanges:(NSMutableArray *)protectedRanges {
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:pattern
                             options:0
                               error:nil];
    NSArray *matches = [regex matchesInString:string.string
                                      options:0
                                        range:NSMakeRange(0, string.string.length)];
    for (NSTextCheckingResult *match in matches) {
        [protectedRanges addObject:[NSValue valueWithRange:match.range]];
    }
}

@end