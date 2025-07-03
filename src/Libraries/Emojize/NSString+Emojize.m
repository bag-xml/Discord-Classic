//
//  NSString+Emojize.m
//  Field Recorder
//
//  Created by Jonathan Beilin on 11/5/12.
//  Copyright (c) 2014 DIY. All rights reserved.
//

#import "NSString+Emojize.h"

@implementation NSString (Emojize)

- (NSString *)emojizedString {
    return [NSString emojizedStringWithString:self];
}

+ (NSString *)emojizedStringWithString:(NSString *)text {
    static dispatch_once_t onceToken;
    static NSRegularExpression *regex = nil;
    dispatch_once(&onceToken, ^{
        regex = [[NSRegularExpression alloc]
            initWithPattern:@"(:[a-z0-9-+_]+:)"
                    options:NSRegularExpressionCaseInsensitive
                      error:NULL];
    });

    __block NSString *resultText = text;

    NSRange matchingRange = NSMakeRange(0, [resultText length]);

    [regex
        enumerateMatchesInString:resultText
                         options:NSMatchingReportCompletion
                           range:matchingRange
                      usingBlock:^(
                          NSTextCheckingResult *result, NSMatchingFlags flags,
                          BOOL *stop
                      ) {
                          if (result
                              && ([result resultType]
                                  == NSTextCheckingTypeRegularExpression)
                              && !(flags & NSMatchingInternalError)) {
                              NSRange range = result.range;
                              if (range.location != NSNotFound) {
                                  NSString *code =
                                      [text substringWithRange:range];

                                  Boolean found     = false;
                                  NSString *unicode = nil;
                                  // search through JSON for emoji
                                  for (NSString *type in self.emojiAliases) {
                                      for (NSDictionary *emojiObject in
                                           [self.emojiAliases
                                               objectForKey:type]) {
                                          for (NSString *name in [emojiObject
                                                   objectForKey:@"names"]) {
                                              if ([[NSString
                                                      stringWithFormat:@":%@:",
                                                                       name]
                                                      isEqualToString:code]) {
                                                  found   = true;
                                                  unicode = [emojiObject
                                                      objectForKey:
                                                          @"surrogates"];
                                                  break;
                                              }
                                          }
                                          if (found) {
                                              break;
                                          }
                                      }
                                      if (found) {
                                          break;
                                      }
                                  }

                                  if (found) {
                                      resultText = [resultText
                                          stringByReplacingOccurrencesOfString:
                                              code
                                                                    withString:
                                                                        unicode];
                                  }
                              }
                          }
                      }];

    return resultText;
}

+ (NSDictionary *)emojiAliases {
    static NSDictionary *_emojiAliases;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"emoji"
                                                         ofType:@"json"];
        NSData *data   = [NSData dataWithContentsOfFile:path];
        _emojiAliases  = [NSJSONSerialization JSONObjectWithData:data
                                                        options:kNilOptions
                                                          error:nil];
    });
    return _emojiAliases;
}

@end
