//
//  DCWebImageOperations.h
//  Discord Classic
//
//  Created by bag.xml on 3/17/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import "DCMessage.h"
#import "DCUser.h"
#import "DCGuild.h"

#define VERSION_MIN(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)


@interface DCTools : NSObject
@property bool oldMode;
+ (void)processImageDataWithURLString:(NSString *)urlString
														 andBlock:(void (^)(UIImage *imageData))processImage;

+ (NSDictionary*)parseJSON:(NSString*)json;
+ (void)alert:(NSString*)title withMessage:(NSString*)message;
+ (NSData*)checkData:(NSData*)response withError:(NSError*)error;

+ (DCMessage*)convertJsonMessage:(NSDictionary*)jsonMessage;
+ (DCGuild *)convertJsonGuild:(NSDictionary*)jsonGuild;
+ (DCUser*)convertJsonUser:(NSDictionary*)jsonUser cache:(bool)cache;

+ (void)joinGuild:(NSString*)inviteCode;
@end
