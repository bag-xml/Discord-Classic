#import "DCServerCommunicator.h"
#import <zlib.h>

@interface DCServerCommunicator () {
    z_stream _inflateStream;
}

@property (assign, nonatomic) BOOL inflateStreamReady;
@property (strong, nonatomic) NSMutableData *compressedBuffer;

@property (strong, nonatomic) UIView *notificationView;
@property (assign, nonatomic) BOOL gotHeartbeat;
@property (assign, nonatomic) BOOL heartbeatDefined;

@property (assign, nonatomic) BOOL canIdentify;

@property (assign, nonatomic) NSInteger sequenceNumber;
@property (strong, nonatomic) NSString *sessionId;

@property (assign, nonatomic) BOOL isReconnecting;
@property (assign, nonatomic) NSInteger reconnectAttempts;
@property (strong, nonatomic) NSTimer *cooldownTimer;
@property (strong, nonatomic) UIAlertView *alertView;
@property (assign, nonatomic) BOOL oldMode;

- (void)showNonIntrusiveNotificationWithTitle:(NSString *)title;
- (void)dismissNotification;
@end