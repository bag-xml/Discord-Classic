//
//  DCLoginManager.m
//  Discord Classic
//
//  Created by Ayeris on 2/28/26.
//  Copyright (c) 2026 Ayeris All rights reserved.
//

#import "DCLoginManager.h"
#import "DCServerCommunicator.h"
//#import <sys/utsname.h>

NSString *const DCLoginErrorTwoFactorTicketKey = @"DCLoginErrorTwoFactorTicketKey";
NSString *const DCLoginErrorServerMessageKey   = @"DCLoginErrorServerMessageKey";
NSString *const DCLoginErrorFingerprintKey = @"DCLoginErrorFingerprintKey";
NSString *const DCLoginErrorInstanceIDKey = @"DCLoginErrorInstanceIDKey";

@implementation DCLoginManager

#pragma mark - Private helpers
 
 // Based off JWI's Neocord project

+ (NSMutableURLRequest *)requestForPath:(NSString *)path {
    return [DCServerCommunicator requestWithPath:path token:nil];
}

+ (NSError *)errorWithCode:(DCLoginErrorCode)code message:(NSString *)message discordCode:(NSInteger)discordCode {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (message) {
        info[DCLoginErrorServerMessageKey] = message;
        info[NSLocalizedDescriptionKey] = message;
    } else {
        info[NSLocalizedDescriptionKey] = @"An unknown error occurred.";
    }
    info[@"discord_code"] = @(discordCode);
    return [NSError errorWithDomain:@"DCLoginErrorDomain" code:code userInfo:info];
}

// Sends a request on a background queue and calls back on main.
+ (void)sendRequest:(NSMutableURLRequest *)request
         completion:(void (^)(NSDictionary *json, NSHTTPURLResponse *response, NSError *error))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSHTTPURLResponse *httpResponse = nil;
        NSError *connError = nil;
        NSData *data = [NSURLConnection sendSynchronousRequest:request
                                             returningResponse:&httpResponse
                                                         error:&connError];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (connError || !data) {
                completion(nil, httpResponse, connError ?: [self errorWithCode:DCLoginErrorCodeNetwork message:nil discordCode:0]);
                return;
            }
            NSError *jsonError = nil;
            id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (jsonError || ![parsed isKindOfClass:[NSDictionary class]]) {
                completion(nil, httpResponse, [self errorWithCode:DCLoginErrorCodeInvalidJSON message:nil discordCode:0]);
                return;
            }
            completion((NSDictionary *)parsed, httpResponse, nil);
        });
    });
}

#pragma mark - Step 1: Fingerprint

+ (void)fetchFingerprintWithCompletion:(void (^)(NSString *fingerprint, NSError *error))completion {
    NSMutableURLRequest *req = [self requestForPath:@"/auth/fingerprint"];
    req.HTTPMethod = @"POST";
    req.HTTPBody   = [NSJSONSerialization dataWithJSONObject:@{} options:0 error:nil];

    [self sendRequest:req completion:^(NSDictionary *json, NSHTTPURLResponse *response, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSString *fingerprint = json[@"fingerprint"];
        if (![fingerprint isKindOfClass:[NSString class]]) {
            completion(nil, [self errorWithCode:DCLoginErrorCodeInvalidJSON message:nil discordCode:0]);
            return;
        }
        completion(fingerprint, nil);
    }];
}

#pragma mark - Step 2: Login

+ (void)loginWithEmail:(NSString *)email
              password:(NSString *)password
            completion:(void (^)(NSString *token, NSError *error))completion {
    // First get a fingerprint, then use it to log in.
    [self fetchFingerprintWithCompletion:^(NSString *fingerprint, NSError *error) {
        if (error) { completion(nil, error); return; }

        NSMutableURLRequest *req = [self requestForPath:@"/auth/login"];
        req.HTTPMethod = @"POST";
        [req setValue:fingerprint forHTTPHeaderField:@"X-Fingerprint"];

        NSDictionary *body = @{
            @"login"          : email,
            @"password"       : password,
            @"undelete"       : @NO,
            @"gift_code_sku_id"   : [NSNull null],
            @"login_source": [NSNull null],
        };
        req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

        [self sendRequest:req completion:^(NSDictionary *json, NSHTTPURLResponse *response, NSError *connErr) {
            if (connErr) { completion(nil, connErr); return; }

            // Success — got a token directly
            NSString *token = json[@"token"];
            if ([token isKindOfClass:[NSString class]] && token.length > 0) {
                completion(token, nil);
                return;
            }

            // 2FA required
            NSString *ticket = json[@"ticket"];
            if ([ticket isKindOfClass:[NSString class]]) {
                NSString *instanceID = json[@"login_instance_id"];
                NSError *twoFactorError = [NSError errorWithDomain:@"DCLoginErrorDomain"
                                                              code:DCLoginErrorCodeTwoFactor
                                                          userInfo:@{
                                                                     DCLoginErrorTwoFactorTicketKey  : ticket,
                                                                     DCLoginErrorFingerprintKey      : fingerprint,
                                                                     DCLoginErrorInstanceIDKey       : instanceID ?: @"",
                                                                     NSLocalizedDescriptionKey       : @"Two-factor authentication required."
                                                                     }];
                completion(nil, twoFactorError);
                return;
            }
            

            // Captcha
            if (json[@"captcha_key"]) {
                completion(nil, [self errorWithCode:DCLoginErrorCodeCaptcha
                                            message:@"Login requires a captcha which cannot be completed on this device."
                                        discordCode:0]);
                return;
            }

            // Discord error
            NSInteger discordCode = [json[@"code"] integerValue];
            NSArray *errors = json[@"errors"];
            NSString *serverMsg = nil;
            if ([errors isKindOfClass:[NSArray class]] && errors.count > 0) {
                serverMsg = [errors componentsJoinedByString:@"\n"];
            }
            if (!serverMsg) {
                serverMsg = json[@"message"];
            }
            completion(nil, [self errorWithCode:DCLoginErrorCodeBadCredentials
                                        message:serverMsg ?: @"Invalid email or password."
                                    discordCode:discordCode]);
        }];
    }];
}

#pragma mark - Step 3: 2FA

+ (void)loginTwoFactorWithCode:(NSString *)code
                        ticket:(NSString *)ticket
                   fingerprint:(NSString *)fingerprint
                    instanceID:(NSString *)instanceID
                    completion:(void (^)(NSString *token, NSError *error))completion {
    NSLog(@"[2FA] fingerprint: '%@' ticket: '%@' code: '%@'", fingerprint, ticket, code);
    NSMutableURLRequest *req = [self requestForPath:@"/auth/mfa/totp"];
    req.HTTPMethod = @"POST";
    [req setValue:fingerprint forHTTPHeaderField:@"X-Fingerprint"];
    
    NSDictionary *body = @{
                           @"code"            : code,
                           @"ticket"          : ticket,
                           @"login_source"    : [NSNull null],
                           @"gift_code_sku_id": [NSNull null],
                           @"login_instance_id" : instanceID.length > 0 ? instanceID : [NSNull null],
                           };
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    
    [self sendRequest:req completion:^(NSDictionary *json, NSHTTPURLResponse *response, NSError *connErr) {
        if (connErr) { completion(nil, connErr); return; }
        
        NSString *token = json[@"token"];
        if ([token isKindOfClass:[NSString class]] && token.length > 0) {
            completion(token, nil);
            return;
        }
        
        NSInteger discordCode = [json[@"code"] integerValue];
        NSString *serverMsg = json[@"message"];
        completion(nil, [self errorWithCode:DCLoginErrorCodeBadCredentials
                                    message:serverMsg ?: @"Invalid two-factor code."
                                discordCode:discordCode]);
    }];
}

@end
