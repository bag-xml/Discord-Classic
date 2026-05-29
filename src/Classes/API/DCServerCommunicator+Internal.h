#import "DCServerCommunicator.h"

@interface DCServerCommunicator ()
@property (strong, nonatomic) UIView *notificationView;
@property (assign, nonatomic) BOOL gotHeartbeat;
@property (assign, nonatomic) BOOL heartbeatDefined;

@property (assign, nonatomic) BOOL canIdentify;

@property (assign, nonatomic) NSInteger sequenceNumber;
@property (strong, nonatomic) NSString *sessionId;

@property (strong, nonatomic) NSTimer *cooldownTimer;
@property (strong, nonatomic) UIAlertView *alertView;
@property (assign, nonatomic) BOOL oldMode;

- (void)showNonIntrusiveNotificationWithTitle:(NSString *)title;
- (void)dismissNotification;
@end