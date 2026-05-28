//
//  DCMessage.m
//  Discord Classic
//
//  Created by bag.xml on 4/7/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import "DCMessage.h"

@implementation DCMessage

- (BOOL)isEqual:(id)other {
    if (!other || ![other isKindOfClass:DCMessage.class]) {
        return NO;
    }

    return [self.snowflake isEqual:((DCMessage *)other).snowflake];
}

@end
