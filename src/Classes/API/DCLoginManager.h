//
//  DCLoginManager.h
//  Discord Classic
//
//  Created by Ayeris on 2/28/26.
//  Copyright (c) 2026 Ayeris All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, DCLoginErrorCode) {
    DCLoginErrorCodeUnknown        = 0,
    DCLoginErrorCodeNetwork        = 1, // NSURLConnection failure
    DCLoginErrorCodeInvalidJSON    = 2, // Couldn't parse server response
    DCLoginErrorCodeBadCredentials = 3, // Wrong email or password
    DCLoginErrorCodeTwoFactor      = 4, // 2FA required — ticket in userInfo
    DCLoginErrorCodeCaptcha        = 5, // hCaptcha required — dead end on iOS 5/6
    DCLoginErrorCodeServerError    = 6, // Discord returned an error message
};

// Keys in NSError.userInfo:
extern NSString *const DCLoginErrorTwoFactorTicketKey; // NSString, when code == TwoFactor
extern NSString *const DCLoginErrorServerMessageKey;   // NSString, human-readable from Discord
extern NSString *const DCLoginErrorFingerprintKey;
extern NSString *const DCLoginErrorInstanceIDKey;

@interface DCLoginManager : NSObject

// Fetches a fingerprint then logs in with email/password.
// Completion called on main queue.
// Success:      token non-nil, error nil
// 2FA needed:   token nil, error.code == DCLoginErrorCodeTwoFactor,
//               error.userInfo[DCLoginErrorTwoFactorTicketKey] has the ticket
+ (void)loginWithEmail:(NSString *)email
              password:(NSString *)password
            completion:(void (^)(NSString *token, NSError *error))completion;

// Exchange a TOTP code + ticket for a token after a 2FA challenge.
// Completion called on main queue.
+ (void)loginTwoFactorWithCode:(NSString *)code
                        ticket:(NSString *)ticket
                   fingerprint:(NSString *)fingerprint
                    instanceID:(NSString *)instanceID
                    completion:(void (^)(NSString *token, NSError *error))completion;

@end
