//
//  DCMarkdownParser.m
//  Discord Classic
//
//  Created by Ayeris on 5/23/26.
//  Copyright (c) 2026 Ayeris All rights reserved.
//
//  Parses Discord markdown into CoreText-compatible NSAttributedStrings.
//  Safe for use on iOS 5+. Add -fobjc-arc to this file's compiler flags
//  in Build Phases > Compile Sources.
//

#import "DCMarkdownParser.h"
#import "DTCoreTextConstants.h"
#import <CoreText/CoreText.h>

// Constants defined here, declared extern in header
NSString *const DCMarkdownBlockTypeAttributeName = @"DCMarkdownBlockType";
NSString *const DCMarkdownSpoilerAttributeName   = @"DCMarkdownSpoiler";

// Internal spoiler URL scheme used with DTCoreText link delegate
static NSString *const kDCSpoilerScheme = @"discord-spoiler";


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
    _subtextColor       = [UIColor colorWithRed:130/255.0f green:133/255.0f blue:137/255.0f alpha:1.0f];
    _strikethroughColor = _defaultColor;
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
    CGFloat minLineHeight = 18.0f;
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
    [self applyMentions:result protectedRanges:protectedRanges];
    [self applyURLDetection:result protectedRanges:protectedRanges];

    return [result copy];
}


#pragma mark - Step 2: Multiline Code Blocks

- (void)applyMultilineCodeBlocks:(NSMutableAttributedString *)string
                  protectedRanges:(NSMutableArray *)protectedRanges {
    NSString *text = string.string;
    NSUInteger length = text.length;
    NSUInteger i = 0;

    while (i + 2 < length) {
        if ([text characterAtIndex:i]     == '`' &&
            [text characterAtIndex:i + 1] == '`' &&
            [text characterAtIndex:i + 2] == '`') {

            NSUInteger openTick = i;
            NSUInteger contentStart = i + 3;

            // Skip optional language identifier on same line
            NSUInteger langEnd = contentStart;
            while (langEnd < length && [text characterAtIndex:langEnd] != '\n') {
                langEnd++;
            }
            if (langEnd < length) langEnd++;
            contentStart = langEnd;

            // Find closing ```
            NSRange closeRange = [text rangeOfString:@"```"
                                             options:0
                                               range:NSMakeRange(contentStart, length - contentStart)];
            if (closeRange.location == NSNotFound) {
                closeRange = NSMakeRange(length, 0);
            }

            NSRange blockRange   = NSMakeRange(openTick, NSMaxRange(closeRange) - openTick);
            NSRange contentRange = NSMakeRange(contentStart, closeRange.location - contentStart);

            NSDictionary *codeAttrs = @{
                (NSString *)kCTFontAttributeName:            [self ctFontRef:_codeFont],
                (NSString *)kCTForegroundColorAttributeName: (__bridge id)_codeTextColor.CGColor,
                DCMarkdownBlockTypeAttributeName:            @(DCMarkdownBlockTypeCode)
            };
            if (contentRange.length > 0 && NSMaxRange(contentRange) <= string.length) {
                [string addAttributes:codeAttrs range:contentRange];
            }

            [protectedRanges addObject:[NSValue valueWithRange:blockRange]];
            i = NSMaxRange(closeRange) > 0 ? NSMaxRange(closeRange) : length;
        } else {
            i++;
        }
    }
}


#pragma mark - Step 3: Block Level Formatting

- (void)applyBlockLevelFormatting:(NSMutableAttributedString *)string
                   protectedRanges:(NSMutableArray *)protectedRanges {
    NSString *text = string.string;
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    NSUInteger lineStart = 0;

    for (NSString *line in lines) {
        NSUInteger lineLength = line.length;
        NSRange lineRange = NSMakeRange(lineStart, lineLength);

        if (![self range:lineRange isProtectedBy:protectedRanges]) {
            [self applyBlockFormattingToLine:line
                                       range:lineRange
                                    inString:string
                             protectedRanges:protectedRanges];
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
        return;
    }
    if ([line hasPrefix:@"## "]) {
        [self addAttributes:[self attributesForFont:_h2Font color:_defaultColor]
                    toRange:lineRange inString:string];
        return;
    }
    if ([line hasPrefix:@"# "]) {
        [self addAttributes:[self attributesForFont:_h1Font color:_defaultColor]
                    toRange:lineRange inString:string];
        return;
    }
    if ([line hasPrefix:@"-# "]) {
        [self addAttributes:[self attributesForFont:_subtextFont color:_subtextColor]
                    toRange:lineRange inString:string];
        return;
    }
    if ([line hasPrefix:@">>> "] || [line hasPrefix:@"> "]) {
        [self addAttributes:@{
            (NSString *)kCTForegroundColorAttributeName: (__bridge id)_blockquoteColor.CGColor,
            DCMarkdownBlockTypeAttributeName:            @(DCMarkdownBlockTypeBlockquote)
        } toRange:lineRange inString:string];
        return;
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
    [self applyInlineCode:string protectedRanges:protectedRanges];

    [self applyPattern:@"\\*\\*\\*(.+?)\\*\\*\\*"
                  font:_boldItalicFont color:nil strikethrough:NO underline:NO
                string:string protectedRanges:protectedRanges];

    [self applyPattern:@"\\*\\*(.+?)\\*\\*"
                  font:_boldFont color:nil strikethrough:NO underline:NO
                string:string protectedRanges:protectedRanges];

    [self applyPattern:@"__(.+?)__"
                  font:_underlineFont color:nil strikethrough:NO underline:YES
                string:string protectedRanges:protectedRanges];

    [self applyPattern:@"(?<!\\*)\\*(?!\\*)(.*?)\\*|(?<!_)_(?!_)(.*?)_"
                  font:_italicFont color:nil strikethrough:NO underline:NO
                string:string protectedRanges:protectedRanges];

    [self applyPattern:@"(?<![a-zA-Z0-9])_(.+?)_(?![a-zA-Z0-9])"
                  font:_italicFont color:nil strikethrough:NO underline:NO
                string:string protectedRanges:protectedRanges];

    [self applyPattern:@"~~(.+?)~~"
                  font:nil color:_strikethroughColor strikethrough:YES underline:NO
                string:string protectedRanges:protectedRanges];

    [self applySpoilers:string protectedRanges:protectedRanges];
    [self applyMarkdownLinks:string protectedRanges:protectedRanges];
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
            (NSString *)kCTFontAttributeName:            [self ctFontRef:_codeFont],
            (NSString *)kCTForegroundColorAttributeName: (__bridge id)_codeTextColor.CGColor
        };
        [string addAttributes:codeAttrs range:match.range];
        [protectedRanges addObject:[NSValue valueWithRange:match.range]];
    }
}

- (void)applyPattern:(NSString *)pattern
                font:(UIFont *)font
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

        NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
        if (font)  attrs[(NSString *)kCTFontAttributeName]            = [self ctFontRef:font];
        if (color) attrs[(NSString *)kCTForegroundColorAttributeName] = (__bridge id)color.CGColor;
        if (underline) {
            attrs[(NSString *)kCTUnderlineStyleAttributeName] = @(kCTUnderlineStyleSingle);
        }
        if (strikethrough) {
            attrs[@"DTStrikethrough"] = @(NSUnderlineStyleSingle);
        }
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

        NSString *encoded = [innerText stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSString *urlString = [NSString stringWithFormat:@"%@://%@", kDCSpoilerScheme, encoded];
        NSURL *spoilerURL = [NSURL URLWithString:urlString];

        NSDictionary *attrs = @{
            (NSString *)kCTForegroundColorAttributeName: (__bridge id)_spoilerHiddenColor.CGColor,
            @"DTLinkAttribute":                                   spoilerURL ?: [NSNull null],
            DCMarkdownSpoilerAttributeName:              innerText
        };
        [string addAttributes:attrs range:match.range];
        [protectedRanges addObject:[NSValue valueWithRange:match.range]];
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
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) continue;

        NSDictionary *attrs = @{
            (NSString *)kCTForegroundColorAttributeName: (__bridge id)_linkColor.CGColor,
            (NSString *)kCTFontAttributeName:            [self ctFontRef:_boldFont],
            DTLinkAttribute:                             url
        };
        
        [string addAttributes:attrs range:match.range];

        [string replaceCharactersInRange:match.range
                              withString:[string.string substringWithRange:textRange]];
        NSRange linkRange = NSMakeRange(match.range.location, textRange.length);
        [string addAttributes:attrs range:linkRange];
        [protectedRanges addObject:[NSValue valueWithRange:linkRange]];
    }
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
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", urlPrefix, entityID]];

        NSDictionary *attrs = @{
            (NSString *)kCTForegroundColorAttributeName: (__bridge id)_mentionColor.CGColor,
            (NSString *)kCTFontAttributeName:            [self ctFontRef:_boldFont],
            @"DTLinkAttribute":                                   url ?: [NSNull null]
        };
        [string addAttributes:attrs range:match.range];
        [protectedRanges addObject:[NSValue valueWithRange:match.range]];
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
            [string addAttribute:(NSString *)kCTFontAttributeName
                           value:[self ctFontRef:_boldFont]
                           range:found];
            [string addAttribute:(NSString *)kCTForegroundColorAttributeName
                           value:(__bridge id)_mentionColor.CGColor
                           range:found];
            [string addAttribute:@"DTBackgroundColor"
                           value:(__bridge id)[UIColor colorWithRed:150/255.0f  green:164/255.0f blue:244/255.0f alpha:0.2f].CGColor
                           range:found];
            [protectedRanges addObject:[NSValue valueWithRange:found]];
        }
        searchRange.location = NSMaxRange(found);
        searchRange.length = text.length - searchRange.location;
    }
}

- (void)applyTimestamps:(NSMutableAttributedString *)string
         protectedRanges:(NSMutableArray *)protectedRanges {
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"<t:([0-9]+)(?::([tTdDfFR]))?>"
                             options:0
                               error:nil];

    NSArray *matches = [regex matchesInString:string.string
                                      options:0
                                        range:NSMakeRange(0, string.string.length)];

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

        [string addAttribute:(NSString *)kCTForegroundColorAttributeName
                       value:(__bridge id)_mentionColor.CGColor
                       range:replacedRange];
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
    } else if ([style isEqualToString:@"R"]) {
        NSTimeInterval delta = [[NSDate date] timeIntervalSinceDate:date];
        if (fabs(delta) < 60)       return @"just now";
        if (fabs(delta) < 3600)     return [NSString stringWithFormat:@"%d minutes ago", (int)(delta / 60)];
        if (fabs(delta) < 86400)    return [NSString stringWithFormat:@"%d hours ago",   (int)(delta / 3600)];
        if (fabs(delta) < 2592000)  return [NSString stringWithFormat:@"%d days ago",    (int)(delta / 86400)];
        if (fabs(delta) < 31536000) return [NSString stringWithFormat:@"%d months ago",  (int)(delta / 2592000)];
        return [NSString stringWithFormat:@"%d years ago", (int)(delta / 31536000)];
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

    for (NSTextCheckingResult *match in matches) {
        if ([self range:match.range isProtectedBy:protectedRanges]) continue;
        
        NSURL *url = match.URL;
        if (!url) {
            NSString *urlString = [string.string substringWithRange:match.range];
            url = [NSURL URLWithString:urlString];
        }
        if (!url) continue;

        NSDictionary *attrs = @{
            (NSString *)kCTForegroundColorAttributeName: (__bridge id)_linkColor.CGColor,
            (NSString *)kCTFontAttributeName:            [self ctFontRef:_boldFont],
            DTLinkAttribute:                             url
        };
        [string addAttributes:attrs range:match.range];
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