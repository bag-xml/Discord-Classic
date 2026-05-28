//
//  UIColorHex.m
//  Discord Classic
//
//  Created by XML on 25/12/24.
//  Copyright (c) 2024 bag.xml. All rights reserved.
//

#import "UIColorHex.h"

@implementation UIColorHex

+ (UIColor *)colorWithHexString:(NSString *)hexString {
    NSString *cleanString = [hexString
        stringByTrimmingCharactersInSet:[NSCharacterSet
                                            whitespaceAndNewlineCharacterSet]];
    if ([cleanString hasPrefix:@"#"]) {
        cleanString = [cleanString substringFromIndex:1];
    }

    if ([cleanString length] != 6) {
        return nil; // invalid hex ssrgttijng
    }

    unsigned int rgbValue = 0;
    [[NSScanner scannerWithString:cleanString] scanHexInt:&rgbValue];

    CGFloat red   = ((rgbValue >> 16) & 0xFF) / 255.0;
    CGFloat green = ((rgbValue >> 8) & 0xFF) / 255.0;
    CGFloat blue  = (rgbValue & 0xFF) / 255.0;

    return [UIColor colorWithRed:red green:green blue:blue alpha:1.0];
}

@end
