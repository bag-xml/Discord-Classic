//
//  DCChatViewController.m
//  Discord Classic
//
//  Created by bag.xml on 3/6/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import "DCChatViewController.h"
#include <dispatch/dispatch.h>
#include <objc/runtime.h>
#include "DCEmoji.h"
#include "SDWebImageManager.h"

#include <Foundation/Foundation.h>
#include <Foundation/NSObjCRuntime.h>
#include <UIKit/UIKit.h>
#include <malloc/malloc.h>
#include <objc/NSObjCRuntime.h>

#import "DCCInfoViewController.h"
#import "DCChatTableCell.h"
#import "DCChatVideoAttachment.h"
#import "DCImageViewController.h"
#import "DCMessage.h"
#import "DCServerCommunicator.h"
#import "DCTools.h"
#import "DCUser.h"
#import "QuickLook/QuickLook.h"
#import "TRMalleableFrameView.h"
#import "UILazyImage.h"
#import "UILazyImageView.h"

@interface DCChatViewController ()
@property (strong, nonatomic) NSMutableArray *messages;
@property (assign, nonatomic) NSUInteger numberOfMessagesLoaded;
@property (strong, nonatomic) UIImage *selectedImage;
@property (assign, nonatomic) BOOL oldMode;
@property (strong, nonatomic) UIRefreshControl *refreshControl;
@property (strong, nonatomic) UIView *typingIndicatorView;
@property (strong, nonatomic) UILabel *typingLabel;
@property (strong, nonatomic) NSMutableDictionary *typingUsers;
@property (assign, nonatomic) CGFloat keyboardHeight;
@property (strong, nonatomic) DCMessage *replyingToMessage;
@property (assign, nonatomic) BOOL disablePing;
@property (strong, nonatomic) DCMessage *editingMessage;
@end

@implementation DCChatViewController
int lastTimeInterval = 0; // for typing indicator

static dispatch_queue_t chat_messages_queue;
- (dispatch_queue_t)get_chat_messages_queue {
    if (chat_messages_queue == nil) {
        chat_messages_queue = dispatch_queue_create(
            [@"Discord::API::Chat::Messages" UTF8String],
            DISPATCH_QUEUE_CONCURRENT
        );
    }
    return chat_messages_queue;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:NO];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    DBGLOG(@"%s: Loading chat view controller", __PRETTY_FUNCTION__);

    UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc]
        initWithTarget:self
                action:@selector(dismissKeyboard:)];
    [self.view addGestureRecognizer:gestureRecognizer];
    gestureRecognizer.cancelsTouchesInView = NO;
    gestureRecognizer.delegate             = self;

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"experimentalMode"]) {
        [UINavigationBar.appearance
            setBackgroundImage:[UIImage imageNamed:@"TbarBG"]
                 forBarMetrics:UIBarMetricsDefault];
        self.slideMenuController.bouncing = YES;
        self.slideMenuController.gestureSupport =
            APLSlideMenuGestureSupportDrag;
        self.slideMenuController.separatorColor = [UIColor grayColor];
        // Go to settings if no token is set
        if (!DCServerCommunicator.sharedInstance.token.length) {
            [self performSegueWithIdentifier:@"to Tokenpage" sender:self];
        }
    }

    self.messages = NSMutableArray.new;

    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(handleMessageCreate:)
               name:@"MESSAGE CREATE"
             object:nil];

    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(handleMessageDelete:)
               name:@"MESSAGE DELETE"
             object:nil];

    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(handleMessageEdit:)
               name:@"MESSAGE EDIT"
             object:nil];

    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(handleTyping:)
               name:@"TYPING START"
             object:nil];

    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(handleStopTyping:)
               name:@"TYPING STOP"
             object:nil];

    // use NUKE/RELOAD CHAT DATA very sparingly, it is very expensive and lags the chat
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleChatReset)
                                               name:@"NUKE CHAT DATA"
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleAsyncReload)
                                               name:@"RELOAD CHAT DATA"
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleReloadUser:)
                                               name:@"RELOAD USER DATA"
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleReloadMessage:)
                                               name:@"RELOAD MESSAGE DATA"
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleReady)
                                               name:@"READY"
                                             object:nil];

    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(keyboardWillShow:)
               name:UIKeyboardWillShowNotification
             object:nil];

    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(keyboardWillHide:)
               name:UIKeyboardWillHideNotification
             object:nil];

    self.oldMode =
        [[NSUserDefaults standardUserDefaults] boolForKey:@"hackyMode"];
    if (self.oldMode == NO) {
        [self.nbbar setBackgroundImage:[UIImage imageNamed:@"TbarBG"]
                         forBarMetrics:UIBarMetricsDefault];
        [self.nbmodaldone setBackgroundImage:[UIImage imageNamed:@"BarButton"]
                                    forState:UIControlStateNormal
                                  barMetrics:UIBarMetricsDefault];
        [self.nbmodaldone
            setBackgroundImage:[UIImage imageNamed:@"BarButtonPressed"]
                      forState:UIControlStateHighlighted
                    barMetrics:UIBarMetricsDefault];

        [[UIToolbar appearance] setBackgroundImage:[UIImage imageNamed:@"ToolbarBG"]
                                forToolbarPosition:UIToolbarPositionAny
                                        barMetrics:UIBarMetricsDefault];

        [self.sidebarButton setBackgroundImage:[UIImage imageNamed:@"BarButton"]
                                      forState:UIControlStateNormal
                                    barMetrics:UIBarMetricsDefault];
        [self.sidebarButton
            setBackgroundImage:[UIImage imageNamed:@"BarButtonPressed"]
                      forState:UIControlStateHighlighted
                    barMetrics:UIBarMetricsDefault];

        [self.memberButton setBackgroundImage:[UIImage imageNamed:@"BarButton"]
                                     forState:UIControlStateNormal
                                   barMetrics:UIBarMetricsDefault];
        [self.memberButton
            setBackgroundImage:[UIImage imageNamed:@"BarButtonPressed"]
                      forState:UIControlStateHighlighted
                    barMetrics:UIBarMetricsDefault];


        [self.sendButton setBackgroundImage:[UIImage imageNamed:@"BarButton"]
                                   forState:UIControlStateNormal
                                 barMetrics:UIBarMetricsDefault];
        [self.sendButton
            setBackgroundImage:[UIImage imageNamed:@"BarButtonPressed"]
                      forState:UIControlStateHighlighted
                    barMetrics:UIBarMetricsDefault];

        [self.photoButton setBackgroundImage:[UIImage imageNamed:@"BarButton"]
                                    forState:UIControlStateNormal
                                  barMetrics:UIBarMetricsDefault];
        [self.photoButton
            setBackgroundImage:[UIImage imageNamed:@"BarButtonPressed"]
                      forState:UIControlStateHighlighted
                    barMetrics:UIBarMetricsDefault];
    }

    lastTimeInterval = 0;

    self.inputField.delegate = self;
    self.inputFieldPlaceholder.text     = DCServerCommunicator.sharedInstance.selectedChannel.writeable
            ? [NSString stringWithFormat:@"Message%@%@",
                                     ![DCServerCommunicator.sharedInstance.selectedChannel.parentGuild.name isEqualToString:@"Direct Messages"]
                                             ? @" #"
                                             : (DCServerCommunicator.sharedInstance.selectedChannel.recipients.count > 2 ? @" " : @" @"),
                                     DCServerCommunicator.sharedInstance.selectedChannel.name]
            : @"No Permission";
    self.toolbar.userInteractionEnabled = DCServerCommunicator.sharedInstance.selectedChannel.writeable;
    self.inputFieldPlaceholder.hidden   = NO;

    self.typingIndicatorView                  = [[UIView alloc] initWithFrame:CGRectMake(
                                                                 0,
                                                                 self.view.frame.size.height - self.view.frame.origin.y - self.toolbar.height - 43,
                                                                 self.view.frame.size.width,
                                                                 20
                                                             )];
    self.typingIndicatorView.backgroundColor  = [UIColor darkGrayColor];
    self.typingIndicatorView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.typingIndicatorView.hidden           = YES;

    self.typingLabel                 = [[UILabel alloc] initWithFrame:CGRectMake(
                                                          8, 0,
                                                          self.typingIndicatorView.frame.size.width - 16,
                                                          20
                                                      )];
    self.typingLabel.font            = [UIFont systemFontOfSize:12];
    self.typingLabel.textColor       = [UIColor lightGrayColor];
    self.typingLabel.backgroundColor = [UIColor clearColor];

    [self.typingIndicatorView addSubview:self.typingLabel];
    [self.view addSubview:self.typingIndicatorView];
    self.typingUsers = [NSMutableDictionary dictionary];

    if (self.oldMode) {
        [self.chatTableView registerNib:[UINib nibWithNibName:@"O-DCChatTableCell"
                                                       bundle:nil]
                 forCellReuseIdentifier:@"OldMode Message Cell"];
        [self.chatTableView registerNib:[UINib nibWithNibName:@"O-DCChatGroupedTableCell"
                                                       bundle:nil]
                 forCellReuseIdentifier:@"OldMode Grouped Message Cell"];
        [self.chatTableView registerNib:[UINib nibWithNibName:@"O-DCChatReplyTableCell"
                                                       bundle:nil]
                 forCellReuseIdentifier:@"OldMode Reply Message Cell"];
        [self.chatTableView registerNib:[UINib nibWithNibName:@"O-DCUniversalTableCell"
                                                       bundle:nil]
                 forCellReuseIdentifier:@"OldMode Universal Typehandler Cell"];
    } else {
        [self.chatTableView registerNib:[UINib nibWithNibName:@"DCChatGroupedTableCell"
                                                       bundle:nil]
                 forCellReuseIdentifier:@"Grouped Message Cell"];
        [self.chatTableView registerNib:[UINib nibWithNibName:@"DCChatTableCell"
                                                       bundle:nil]
                 forCellReuseIdentifier:@"Message Cell"];
        [self.chatTableView registerNib:[UINib nibWithNibName:@"DCChatReplyTableCell"
                                                       bundle:nil]
                 forCellReuseIdentifier:@"Reply Message Cell"];
        [self.chatTableView registerNib:[UINib nibWithNibName:@"DCUniversalTableCell"
                                                       bundle:nil]
                 forCellReuseIdentifier:@"Universal Typehandler Cell"];
    }
}

- (BOOL)textViewShouldBeginEditing:(UITextView *)textView {
    self.inputFieldPlaceholder.hidden = self.inputField.text.length != 0;
    lastTimeInterval                  = 0;
    return YES;
}

- (void)textViewDidChange:(UITextView *)textView {
    self.inputFieldPlaceholder.hidden = self.inputField.text.length != 0;
    int currentTimeInterval           = [[NSDate date] timeIntervalSince1970];
    if (currentTimeInterval - lastTimeInterval >= 10) {
        [DCServerCommunicator.sharedInstance
                .selectedChannel sendTypingIndicator];
        lastTimeInterval = currentTimeInterval;
    }
}

- (void)textViewDidEndEditing:(UITextView *)textView {
    self.inputFieldPlaceholder.hidden = self.inputField.text.length != 0;
    lastTimeInterval                  = 0;
}

- (void)handleChatReset {
    assertMainThread();
    DBGLOG(@"%s: Resetting chat data", __PRETTY_FUNCTION__);
    @autoreleasepool {
        self.selectedMessage = nil;
        self.selectedImage = nil;
        self.typingUsers = [NSMutableDictionary dictionary];
        self.replyingToMessage = nil;
        self.editingMessage = nil;
        [self.messages removeAllObjects];
        self.numberOfMessagesLoaded = 0;
        self.disablePing = NO;
    }
    self.inputFieldPlaceholder.text     = DCServerCommunicator.sharedInstance.selectedChannel.writeable
            ? [NSString stringWithFormat:@"Message%@%@",
                                     ![DCServerCommunicator.sharedInstance.selectedChannel.parentGuild.name isEqualToString:@"Direct Messages"]
                                             ? @" #"
                                             : (DCServerCommunicator.sharedInstance.selectedChannel.recipients.count > 2 ? @" " : @" @"),
                                     DCServerCommunicator.sharedInstance.selectedChannel.name]
            : @"No Permission";
    self.toolbar.userInteractionEnabled = DCServerCommunicator.sharedInstance.selectedChannel.writeable;
    self.typingIndicatorView.hidden     = YES;
    self.chatTableView.height = self.view.height - self.keyboardHeight - self.toolbar.height;
    self.typingIndicatorView.y = self.view.height - self.keyboardHeight - self.toolbar.height - 20;
    [self.chatTableView
        setContentOffset:CGPointMake(
                             0,
                             self.chatTableView.contentSize.height
                                 - self.chatTableView.frame.size.height
                         )
                animated:NO];
    [self handleAsyncReload];
    // [DCServerCommunicator.sharedInstance description];
}

- (void)handleAsyncReload {
    if (!self.chatTableView) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        // NSLog(@"async reload!");
        //  about contact CoreControl
        @autoreleasepool {
            [self.chatTableView reloadData];
        }
    });
}

- (void)handleReady {
    assertMainThread();
    if (DCServerCommunicator.sharedInstance.selectedChannel) {
        @autoreleasepool {
            [self.messages removeAllObjects];
        }
        self.inputFieldPlaceholder.text     = DCServerCommunicator.sharedInstance.selectedChannel.writeable
                ? [NSString stringWithFormat:@"Message%@%@",
                                         ![DCServerCommunicator.sharedInstance.selectedChannel.parentGuild.name isEqualToString:@"Direct Messages"]
                                                 ? @" #"
                                                 : (DCServerCommunicator.sharedInstance.selectedChannel.recipients.count > 2 ? @" " : @" @"),
                                         DCServerCommunicator.sharedInstance.selectedChannel.name]
                : @"No Permission";
        self.toolbar.userInteractionEnabled = DCServerCommunicator.sharedInstance.selectedChannel.writeable;
        [self handleAsyncReload];
        [self getMessages:50 beforeMessage:nil];
    }

    if (VERSION_MIN(@"6.0") && self.refreshControl) {
        [self.refreshControl endRefreshing];
    }
}

- (BOOL)scrollWithIndex:(NSIndexPath *)idx {
    [self.chatTableView visibleCells];
    NSArray *visibleIdx = [self.chatTableView indexPathsForVisibleRows];
    if ([visibleIdx containsObject:idx]) {
        [self.chatTableView
            setContentOffset:CGPointMake(
                                 0,
                                 self.chatTableView.contentSize.height
                                     - self.chatTableView.frame.size.height
                             )
                    animated:NO];
        return YES;
    }
    return NO;
}

- (void)handleReloadUser:(NSNotification *)notification {
    assertMainThread();
    if (!self.chatTableView) {
        return;
    }

    NSInteger rowCount = [self.chatTableView numberOfRowsInSection:0];
    if (rowCount != self.messages.count) {
        NSLog(@"%s: Row count mismatch! Expected %ld but got %ld", __PRETTY_FUNCTION__, (long)self.messages.count, (long)rowCount);
        [self handleAsyncReload];
        return;
    }

    DCUser *user               = notification.object;
    NSMutableArray *indexPaths = NSMutableArray.new;
    for (int i = 0; i < self.messages.count; i++) {
        DCMessage *message = [self.messages objectAtIndex:i];
        if ([message.author.snowflake isEqualToString:user.snowflake]
            || [message.referencedMessage.author.snowflake isEqualToString:user.snowflake]) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:0];
            [indexPaths addObject:indexPath];
        }
    }
    [self.chatTableView beginUpdates];
    [self.chatTableView reloadRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
    [self.chatTableView endUpdates];
    for (NSIndexPath *indexPath in indexPaths) {
        if ([self scrollWithIndex:indexPath]) {
            break;
        }
    }
}

- (void)handleReloadMessage:(NSNotification *)notification {
    assertMainThread();
    if (!self.chatTableView) {
        return;
    }

    NSInteger rowCount = [self.chatTableView numberOfRowsInSection:0];
    if (rowCount != self.messages.count) {
        NSLog(@"%s: Row count mismatch! Expected %ld but got %ld", __PRETTY_FUNCTION__, (long)self.messages.count, (long)rowCount);
        [self handleAsyncReload];
        return;
    }

    DCMessage *message = notification.object;
    NSUInteger index   = [self.messages indexOfObject:message];
    if (index == NSNotFound || index >= self.messages.count) {
        return;
    }
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
    [self.chatTableView beginUpdates];
    [self.chatTableView reloadRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self.chatTableView endUpdates];
    [self scrollWithIndex:indexPath];
}

- (void)handleMessageCreate:(NSNotification *)notification {
    assertMainThread();
    DCMessage *newMessage = [DCTools convertJsonMessage:notification.userInfo];

    if (!newMessage.author.profileImage) {
        [DCTools getUserAvatar:newMessage.author];
    }

    if (self.messages.count > 0) {
        DCMessage *prevMessage =
            [self.messages objectAtIndex:self.messages.count - 1];
        if (prevMessage != nil) {
            NSDate *currentTimeStamp = newMessage.timestamp;

            if (prevMessage.author.snowflake == newMessage.author.snowflake
                && ([newMessage.timestamp timeIntervalSince1970] -
                        [prevMessage.timestamp timeIntervalSince1970]
                    < 420)
                && [[NSCalendar currentCalendar]
                    rangeOfUnit:NSCalendarUnitDay
                      startDate:&currentTimeStamp
                       interval:NULL
                        forDate:prevMessage.timestamp]
                && (prevMessage.messageType == DCMessageTypeDefault || prevMessage.messageType == DCMessageTypeReply)) {
                newMessage.isGrouped = (newMessage.messageType == DCMessageTypeDefault || newMessage.messageType == DCMessageTypeReply)
                    && (newMessage.referencedMessage == nil);

                if (newMessage.isGrouped) {
                    float contentWidth =
                        UIScreen.mainScreen.bounds.size.width - 63;
                    CGSize authorNameSize = [newMessage.author.globalName
                             sizeWithFont:[UIFont boldSystemFontOfSize:15]
                        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                            lineBreakMode:(NSLineBreakMode)UILineBreakModeWordWrap];

                    newMessage.contentHeight -= authorNameSize.height + 4;
                }
            }
        }
    }

    NSInteger rowCount = [self.chatTableView numberOfRowsInSection:0];
    [self.messages addObject:newMessage];
    NSIndexPath *newIndexPath = [NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0];
    if (rowCount != self.messages.count - 1) {
        NSLog(@"%s: Row count mismatch! Expected %ld but got %ld", __PRETTY_FUNCTION__, (long)self.messages.count, (long)rowCount);
        [self handleAsyncReload];
    } else {
        [self.chatTableView beginUpdates];
        [self.chatTableView insertRowsAtIndexPaths:@[ newIndexPath ] withRowAnimation:UITableViewRowAnimationNone];
        [self.chatTableView endUpdates];
    }

    [self scrollWithIndex:newIndexPath];

    [NSNotificationCenter.defaultCenter
        postNotificationName:@"TYPING STOP"
                      object:newMessage.author.snowflake];

    [NSNotificationCenter.defaultCenter
        postNotificationName:@"MESSAGE DELETE"
                      object:nil
                    userInfo:@{@"id" : ((DCMessage *)self.messages.firstObject).snowflake}];
}

- (void)handleMessageEdit:(NSNotification *)notification {
    assertMainThread();
    NSString *snowflake = [notification.userInfo objectForKey:@"id"];
    if (!snowflake || snowflake.length == 0) {
        NSLog(@"%s: No snowflake provided for message edit", __PRETTY_FUNCTION__);
        return;
    }
    NSUInteger index = [self.messages indexOfObjectPassingTest:^BOOL(DCMessage *msg, NSUInteger idx, BOOL *stop) {
        return [msg.snowflake isEqualToString:snowflake];
    }];
    if (index == NSNotFound || index >= self.messages.count) {
        NSLog(@"%s: Message with snowflake %@ not found", __PRETTY_FUNCTION__, snowflake);
        return;
    }
    DCMessage *compareMessage = [self.messages objectAtIndex:index];

    DCMessage *newMessage = [DCTools convertJsonMessage:notification.userInfo];

    // fix any potential missing fields from a partial response
    if (newMessage.author == nil || (NSNull *)newMessage.author == [NSNull null]) {
        newMessage.author = compareMessage.author;
        newMessage.contentHeight +=
            compareMessage.contentHeight; // assume it's an embed update
    }
    if (newMessage.content == nil || (NSNull *)newMessage.content == [NSNull null]) {
        newMessage.content = compareMessage.content;
    }
    if ((newMessage.attachments == nil || (NSNull *)newMessage.attachments == [NSNull null])
        && newMessage.attachmentCount > 0) {
        newMessage.attachments = compareMessage.attachments;
    }
    newMessage.timestamp = compareMessage.timestamp;
    if (newMessage.editedTimestamp == nil
        || (NSNull *)newMessage.editedTimestamp == [NSNull null]) {
        newMessage.editedTimestamp = compareMessage.editedTimestamp;
    }
    newMessage.prettyTimestamp   = compareMessage.prettyTimestamp;
    newMessage.referencedMessage = compareMessage.referencedMessage;

    if (self.messages.count > 0) {
        NSUInteger curIdx      = [self.messages indexOfObject:compareMessage];
        DCMessage *prevMessage = curIdx != NSNotFound ? [self.messages objectAtIndex:curIdx - 1] : nil;
        if (prevMessage != nil) {
            NSDate *currentTimeStamp = newMessage.timestamp;

            if (prevMessage.author.snowflake == newMessage.author.snowflake
                && ([newMessage.timestamp timeIntervalSince1970] -
                        [prevMessage.timestamp timeIntervalSince1970]
                    < 420)
                && [[NSCalendar currentCalendar]
                    rangeOfUnit:NSCalendarUnitDay
                      startDate:&currentTimeStamp
                       interval:NULL
                        forDate:prevMessage.timestamp]
                && (prevMessage.messageType == DCMessageTypeDefault || prevMessage.messageType == DCMessageTypeReply)) {
                newMessage.isGrouped = (newMessage.messageType == DCMessageTypeDefault || newMessage.messageType == DCMessageTypeReply) && (newMessage.referencedMessage == nil);

                if (newMessage.isGrouped) {
                    float contentWidth =
                        UIScreen.mainScreen.bounds.size.width - 63;
                    CGSize authorNameSize = [newMessage.author.globalName
                             sizeWithFont:[UIFont boldSystemFontOfSize:15]
                        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                            lineBreakMode:(NSLineBreakMode)UILineBreakModeWordWrap];

                    newMessage.contentHeight -= authorNameSize.height + 4;
                }
            }
        }
    }

    NSInteger rowCount = [self.chatTableView numberOfRowsInSection:0];
    NSUInteger idx     = [self.messages indexOfObject:compareMessage];
    if (rowCount != self.messages.count) {
        NSLog(@"%s: Row count mismatch! Expected %ld but got %ld", __PRETTY_FUNCTION__, (long)self.messages.count, (long)rowCount);
        [self.messages replaceObjectAtIndex:idx
                                 withObject:newMessage];
        [self handleAsyncReload];
        return;
    }
    [self.chatTableView beginUpdates];
    [self.messages replaceObjectAtIndex:idx
                             withObject:newMessage];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:idx inSection:0];
    [self.chatTableView reloadRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self.chatTableView endUpdates];
    [self scrollWithIndex:indexPath];
}

- (void)handleMessageDelete:(NSNotification *)notification {
    assertMainThread();
    if (!self.messages || self.messages.count == 0) {
        return;
    }

    NSUInteger index = [self.messages indexOfObjectPassingTest:^BOOL(DCMessage *msg, NSUInteger idx, BOOL *stop) {
        return [msg.snowflake isEqualToString:[notification.userInfo objectForKey:@"id"]];
    }];
    if (index == NSNotFound || index >= self.messages.count) {
        return;
    }

    NSInteger rowCount = [self.chatTableView numberOfRowsInSection:0];
    if (rowCount != self.messages.count) {
        NSLog(@"%s: Row count mismatch! Expected %ld but got %ld", __PRETTY_FUNCTION__, (long)self.messages.count, (long)rowCount);
        [self.messages removeObjectAtIndex:index];
        [self handleAsyncReload];
    } else {
        [self.chatTableView beginUpdates];
        [self.messages removeObjectAtIndex:index];
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
        [self.chatTableView deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
        [self.chatTableView endUpdates];
    }

    if (index + 1 >= self.messages.count) {
        return;
    }
    DCMessage *newMessage = [self.messages objectAtIndex:index + 1];

    if (index <= 0) {
        return;
    }
    DCMessage *prevMessage = [self.messages objectAtIndex:index - 1];

    NSDate *currentTimeStamp = newMessage.timestamp;
    if (prevMessage.author.snowflake == newMessage.author.snowflake
        && ([newMessage.timestamp timeIntervalSince1970] -
                [prevMessage.timestamp timeIntervalSince1970]
            < 420)
        && [[NSCalendar currentCalendar]
            rangeOfUnit:NSCalendarUnitDay
              startDate:&currentTimeStamp
               interval:NULL
                forDate:prevMessage.timestamp]
        && (prevMessage.messageType == DCMessageTypeDefault || prevMessage.messageType == DCMessageTypeReply)) {
        Boolean oldGroupedFlag = newMessage.isGrouped;
        newMessage.isGrouped   = (newMessage.messageType == DCMessageTypeDefault || newMessage.messageType == DCMessageTypeReply) && (newMessage.referencedMessage == nil);

        if (newMessage.isGrouped
            && (newMessage.isGrouped != oldGroupedFlag)) {
            float contentWidth =
                UIScreen.mainScreen.bounds.size.width - 63;
            CGSize authorNameSize = [newMessage.author.globalName
                     sizeWithFont:[UIFont boldSystemFontOfSize:15]
                constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                    lineBreakMode:(NSLineBreakMode)UILineBreakModeWordWrap];

            newMessage.contentHeight -= authorNameSize.height + 4;
        }
    } else if (newMessage.isGrouped) {
        newMessage.isGrouped = false;
        float contentWidth =
            UIScreen.mainScreen.bounds.size.width - 63;
        CGSize authorNameSize = [newMessage.author.globalName
                 sizeWithFont:[UIFont boldSystemFontOfSize:15]
            constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                lineBreakMode:(NSLineBreakMode)UILineBreakModeWordWrap];
        newMessage.contentHeight += authorNameSize.height + 4;
    }
}

- (void)handleTyping:(NSNotification *)notification {
    if (!self.typingIndicatorView) {
        DBGLOG(@"%s: Typing indicator view is not initialized", __PRETTY_FUNCTION__);
        return;
    }

    NSString *typingUserId = notification.object;
    if (!typingUserId) {
        DBGLOG(@"%s: No typing user provided", __PRETTY_FUNCTION__);
        return;
    }

    if ([typingUserId isEqualToString:DCServerCommunicator.sharedInstance.snowflake]) {
        // Ignore typing events from the current user
        return;
    }

    NSTimer *existingTimer = [self.typingUsers objectForKey:typingUserId];
    if (existingTimer) {
        [existingTimer invalidate];
        [self.typingUsers removeObjectForKey:typingUserId];
    }

    self.typingUsers[typingUserId] = [NSTimer scheduledTimerWithTimeInterval:10.0
                                                                      target:self
                                                                    selector:@selector(typingTimerFired:)
                                                                    userInfo:typingUserId
                                                                     repeats:NO];
    // NSLog(@"%s: User %@ is typing, count: %lu", __PRETTY_FUNCTION__, ((DCUser *)[DCServerCommunicator.sharedInstance.loadedUsers objectForKey:typingUserId]).globalName, (unsigned long)self.typingUsers.count);
    [self updateTypingIndicator];
}

- (void)typingTimerFired:(NSTimer *)timer {
    NSString *typingUserId = timer.userInfo;
    [NSNotificationCenter.defaultCenter
        postNotificationName:@"TYPING STOP"
                      object:typingUserId];
}

- (void)handleStopTyping:(NSNotification *)notification {
    if (!self.typingIndicatorView) {
        DBGLOG(@"%s: Typing indicator view is not initialized", __PRETTY_FUNCTION__);
        return;
    }

    NSString *typingUserId = notification.object;
    if (!typingUserId) {
        DBGLOG(@"%s: No typing user provided", __PRETTY_FUNCTION__);
        return;
    }

    if ([typingUserId isEqualToString:DCServerCommunicator.sharedInstance.snowflake]) {
        // Ignore typing events from the current user
        return;
    }

    NSTimer *existingTimer = [self.typingUsers objectForKey:typingUserId];
    if (existingTimer) {
        [existingTimer invalidate];
        [self.typingUsers removeObjectForKey:typingUserId];
    }
    // NSLog(@"%s: User %@ stopped typing, count: %lu", __PRETTY_FUNCTION__, ((DCUser *)[DCServerCommunicator.sharedInstance.loadedUsers objectForKey:typingUserId]).globalName, (unsigned long)self.typingUsers.count);
    [self updateTypingIndicator];
}

- (void)updateTypingIndicator {
    assertMainThread();
    if (self.typingUsers.count == 0) {
        [self.chatTableView
            setHeight:self.view.height - self.keyboardHeight - self.toolbar.height];
        self.typingIndicatorView.hidden = YES;
        return;
    }

    NSMutableArray *typingNames = [NSMutableArray array];
    for (NSString *userId in self.typingUsers.allKeys) {
        DCUser *user = [DCServerCommunicator.sharedInstance.loadedUsers objectForKey:userId];
        if (user) {
            [typingNames addObject:user.globalName];
        }
    }

    NSString *typingText;
    if (typingNames.count == 1) {
        typingText = [NSString stringWithFormat:@"%@ is typing...", typingNames.firstObject];
    } else if (typingNames.count == 2) {
        typingText = [NSString stringWithFormat:@"%@ and %@ are typing...", typingNames[0], typingNames[1]];
    } else if (typingNames.count == 3) {
        typingText = [NSString stringWithFormat:@"%@, %@, and %@ are typing...", typingNames[0], typingNames[1], typingNames[2]];
    } else {
        typingText = @"Several users are typing...";
    }

    self.typingLabel.text           = typingText;
    BOOL wasHidden                  = self.typingIndicatorView.hidden;
    self.typingIndicatorView.hidden = NO;
    [self.typingIndicatorView setNeedsDisplay];
    self.chatTableView.contentOffset = CGPointMake(
        0,
        self.chatTableView.contentOffset.y + (wasHidden ? 20 : 0)
    );
    [self.chatTableView
        setHeight:self.view.height - self.keyboardHeight - 20 - self.toolbar.height];
    [self.typingIndicatorView setY:self.view.height - self.keyboardHeight - self.toolbar.height - 20];
}

- (void)getMessages:(int)numberOfMessages beforeMessage:(DCMessage *)message {
    dispatch_async([self get_chat_messages_queue], ^{
        NSArray *newMessages =
            [DCServerCommunicator.sharedInstance.selectedChannel
                  getMessages:numberOfMessages
                beforeMessage:message];

        if (!newMessages) {
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            NSRange range        = NSMakeRange(0, [newMessages count]);
            NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:range];

            NSInteger rowCount = [self.chatTableView numberOfRowsInSection:0];
            if (rowCount != self.messages.count) {
                NSLog(@"%s: Row count mismatch! Expected %ld but got %ld", __PRETTY_FUNCTION__, (long)self.messages.count, (long)rowCount);
                [self.messages insertObjects:newMessages atIndexes:indexSet];
                [self handleAsyncReload];
            } else {
                NSMutableArray *indexPaths = [[NSMutableArray alloc] init];
                [indexSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *_Nonnull stop) {
                    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:idx inSection:0];
                    [indexPaths addObject:indexPath];
                }];
                [self.chatTableView beginUpdates];
                [self.messages insertObjects:newMessages atIndexes:indexSet];
                [self.chatTableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
                [self.chatTableView endUpdates];
            }
        });

        int scrollOffset = -self.chatTableView.height;
        for (DCMessage *newMessage in newMessages) {
            @autoreleasepool {
                if (!newMessage.author.profileImage) {
                    [DCTools getUserAvatar:newMessage.author];
                }

                int attachmentHeight = 0;
                for (id attachment in newMessage.attachments) {
                    if ([attachment isKindOfClass:[UILazyImage class]]) {
                        UIImage *image      = ((UILazyImage *)attachment).image;
                        CGFloat aspectRatio = image.size.width
                            / image.size.height;
                        int newWidth  = 200 * aspectRatio;
                        int newHeight = 200;
                        if (newWidth > self.chatTableView.width - 66) {
                            newWidth  = self.chatTableView.width - 66;
                            newHeight = newWidth / aspectRatio;
                        }
                        attachmentHeight += newHeight;
                    } else if ([attachment isKindOfClass:[DCChatVideoAttachment class]]) {
                        DCChatVideoAttachment *video = attachment;
                        CGFloat aspectRatio          = video.thumbnail.image.size.width
                            / video.thumbnail.image.size.height;
                        int newWidth  = 200 * aspectRatio;
                        int newHeight = 200;
                        if (newWidth > self.chatTableView.width - 66) {
                            newWidth  = self.chatTableView.width - 66;
                            newHeight = newWidth / aspectRatio;
                        }
                        attachmentHeight += newHeight;
                    } else if ([attachment isKindOfClass:[NSArray class]]) {
                        NSArray *dimensions = attachment;
                        if (dimensions.count == 2) {
                            int width  = [dimensions[0] intValue];
                            int height = [dimensions[1] intValue];
                            if (width <= 0 || height <= 0) {
                                continue;
                            }
                            CGFloat aspectRatio = (CGFloat)width / height;
                            int newWidth        = 200 * aspectRatio;
                            int newHeight       = 200;
                            if (newWidth > self.chatTableView.width - 66) {
                                newWidth  = self.chatTableView.width - 66;
                                newHeight = newWidth / aspectRatio;
                            }
                            attachmentHeight += newHeight;
                        }
                    }
                }
                scrollOffset += newMessage.contentHeight
                    + attachmentHeight
                    + (attachmentHeight ? 11 : 0);
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.chatTableView
                setContentOffset:CGPointMake(0, scrollOffset)
                        animated:NO];

            if ([newMessages count] > 0 && !self.refreshControl) {
                self.refreshControl = UIRefreshControl.new;
                self.refreshControl.attributedTitle =
                    [[NSAttributedString alloc]
                        initWithString:@"Earlier messages"];

                [self.chatTableView addSubview:self.refreshControl];

                [self.refreshControl addTarget:self
                                        action:@selector(get50MoreMessages:)
                              forControlEvents:UIControlEventValueChanged];

                self.refreshControl.autoresizingMask =
                    UIViewAutoresizingFlexibleLeftMargin
                    | UIViewAutoresizingFlexibleRightMargin;
            }
            if (self.refreshControl) {
                [self.refreshControl endRefreshing];
            }
        });
    });
}


- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DCChatTableCell *cell;

    @autoreleasepool {
        if (!self.messages || [self.messages count] <= indexPath.row) {
            NSCAssert(self.messages, @"Messages array is nil");
            NSCAssert([self.messages count] > indexPath.row, @"Invalid indexPath");
        }
        DCMessage *messageAtRowIndex = [self.messages objectAtIndex:indexPath.row];

        if (self.oldMode) {
            NSSet *specialMessageTypes =
                [NSSet setWithArray:@[ @1, @2, @3, @4, @5, @6, @7, @8, @18 ]];

            if (messageAtRowIndex.isGrouped
                && ![specialMessageTypes
                    containsObject:@(messageAtRowIndex.messageType)]) {
                cell = [tableView dequeueReusableCellWithIdentifier:
                                      @"OldMode Grouped Message Cell"];
            } else if (messageAtRowIndex.referencedMessage != nil) {
                cell = [tableView dequeueReusableCellWithIdentifier:
                                      @"OldMode Reply Message Cell"];
            } else if ([specialMessageTypes
                           containsObject:@(messageAtRowIndex.messageType)]) {
                cell = [tableView dequeueReusableCellWithIdentifier:
                                      @"OldMode Universal Typehandler Cell"];
            } else {
                cell = [tableView
                    dequeueReusableCellWithIdentifier:@"OldMode Message Cell"];
            }

            if (messageAtRowIndex.referencedMessage != nil) {
                cell.referencedAuthorLabel.text = messageAtRowIndex.referencedMessage.author.globalName;
                cell.referencedMessage.text     = messageAtRowIndex.referencedMessage.content;
                cell.referencedMessage.frame    = CGRectMake(
                    messageAtRowIndex.referencedMessage.authorNameWidth,
                    cell.referencedMessage.y,
                    self.chatTableView.width - messageAtRowIndex.authorNameWidth,
                    cell.referencedMessage.height
                );

                if (messageAtRowIndex.referencedMessage.author.profileImage) {
                    cell.referencedProfileImage.image =
                        messageAtRowIndex.referencedMessage.author.profileImage;
                } else {
                    [DCTools getUserAvatar:messageAtRowIndex.referencedMessage.author];
                }
            }

            if (!messageAtRowIndex.isGrouped) {
                cell.authorLabel.text = messageAtRowIndex.author.globalName;
            }

            cell.contentTextView.text = messageAtRowIndex.content;

            cell.contentTextView.height = [cell.contentTextView
                                              sizeThatFits:CGSizeMake(
                                                               cell.contentTextView.width, MAXFLOAT
                                                           )]
                                              .height;

            if (!messageAtRowIndex.isGrouped) {
                cell.profileImage.image = messageAtRowIndex.author.profileImage;
            }

            cell.contentView.backgroundColor = messageAtRowIndex.pingingUser
                ? [UIColor redColor]
                : [UIColor clearColor];

            // NSLog(@"%@", cell.subviews);
            for (UIView *subView in cell.subviews) {
                @autoreleasepool {
                    if ([subView isKindOfClass:[UILazyImageView class]]
                     || [subView isKindOfClass:[DCChatVideoAttachment class]]
                     || [subView isKindOfClass:[QLPreviewController class]]
                     || [subView isKindOfClass:[UIActivityIndicatorView class]]
                        ) {
                        [subView removeFromSuperview];
                    }
                }
            }
            // dispatch_async(dispatch_get_main_queue(), ^{
            int imageViewOffset = cell.contentTextView.height + 37;

            for (id attachment in messageAtRowIndex.attachments) {
                @autoreleasepool {
                    if ([attachment isKindOfClass:[UILazyImage class]]) {
                        UILazyImage *lazyImage     = attachment;
                        UILazyImageView *imageView = [UILazyImageView new];
                        imageView.frame            = CGRectMake(
                            11, imageViewOffset,
                            self.chatTableView.width - 22, 200
                        );
                        imageView.image       = lazyImage.image;
                        imageView.contentMode = UIViewContentModeScaleAspectFit;
                        imageView.imageURL    = lazyImage.imageURL;

                        imageViewOffset += imageView.height + 11;

                        UITapGestureRecognizer *singleTap =
                            [[UITapGestureRecognizer alloc]
                                initWithTarget:self
                                        action:@selector(tappedImage:)];
                        singleTap.numberOfTapsRequired   = 1;
                        imageView.userInteractionEnabled = YES;
                        [imageView addGestureRecognizer:singleTap];

                        [cell addSubview:imageView];
                    } else if ([attachment
                                   isKindOfClass:[DCChatVideoAttachment class]]) {
                        ////NSLog(@"add video!");
                        DCChatVideoAttachment *video = attachment;

                        UITapGestureRecognizer *singleTap =
                            [[UITapGestureRecognizer alloc]
                                initWithTarget:self
                                        action:@selector(tappedVideo:)];
                        singleTap.numberOfTapsRequired = 1;
                        [video.playButton addGestureRecognizer:singleTap];
                        video.playButton.userInteractionEnabled = YES;

                        CGFloat aspectRatio = video.thumbnail.image.size.width /
                            video.thumbnail.image.size.height;
                        int newWidth  = 200 * aspectRatio;
                        int newHeight = 200;
                        if (newWidth > self.chatTableView.width - 66) {
                            newWidth  = self.chatTableView.width - 66;
                            newHeight = newWidth / aspectRatio;
                        }
                        video.frame = CGRectMake(55, imageViewOffset, newWidth, newHeight);

                        imageViewOffset += newHeight;

                        [cell addSubview:video];
                    } else if ([attachment isKindOfClass:[QLPreviewController class]]) {
                        ////NSLog(@"Add QuickLook!");
                        QLPreviewController *preview = attachment;

                        /*UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer
                         alloc] initWithTarget:self action:@selector(tappedVideo:)];
                         singleTap.numberOfTapsRequired = 1;
                         [video.playButton addGestureRecognizer:singleTap];
                         video.playButton.userInteractionEnabled = YES;

                         CGFloat aspectRatio = video.thumbnail.image.size.width /
                         video.thumbnail.image.size.height; int newWidth = 200 *
                         aspectRatio; int newHeight = 200; if (newWidth >
                         self.chatTableView.width - 66) { newWidth =
                         self.chatTableView.width - 66; newHeight = newWidth /
                         aspectRatio;
                         }
                         [video setFrame:CGRectMake(55, imageViewOffset, newWidth,
                         newHeight)];*/

                        imageViewOffset += 210;

                        [cell addSubview:preview.view];
                    } else if ([attachment isKindOfClass:[NSArray class]]) {
                        NSArray *dimensions = attachment;
                        if (dimensions.count == 2) {
                            int width  = [dimensions[0] intValue];
                            int height = [dimensions[1] intValue];
                            if (width <= 0 || height <= 0) {
                                continue;
                            }
                            CGFloat aspectRatio = (CGFloat)width / height;
                            int newWidth        = 200 * aspectRatio;
                            int newHeight       = 200;
                            if (newWidth > self.chatTableView.width - 66) {
                                newWidth  = self.chatTableView.width - 66;
                                newHeight = newWidth / aspectRatio;
                            }
                            UIActivityIndicatorView *activityIndicator =
                                [[UIActivityIndicatorView alloc]
                                    initWithActivityIndicatorStyle:
                                        UIActivityIndicatorViewStyleWhite];
                            [activityIndicator setFrame:CGRectMake(
                                                            11, imageViewOffset, newWidth,
                                                            newHeight
                                                        )];
                            [activityIndicator setContentMode:UIViewContentModeScaleAspectFit];
                            imageViewOffset += newHeight + 11;

                            [cell addSubview:activityIndicator];
                            [activityIndicator startAnimating];
                        }
                    }
                }
            }
        } else {
            static NSSet *specialMessageTypes = nil;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                specialMessageTypes = [NSSet setWithArray:@[ @1, @2, @3, @4, @5, @6, @7, @8, @18 ]];
            });

            // TICK(init);
            if (messageAtRowIndex.isGrouped
                && ![specialMessageTypes
                    containsObject:@(messageAtRowIndex.messageType)]) {
                cell = [tableView
                    dequeueReusableCellWithIdentifier:@"Grouped Message Cell"];
            } else if (messageAtRowIndex.referencedMessage != nil) {
                cell = [tableView
                    dequeueReusableCellWithIdentifier:@"Reply Message Cell"];
            } else if ([specialMessageTypes
                           containsObject:@(messageAtRowIndex.messageType)]) {
                cell = [tableView dequeueReusableCellWithIdentifier:
                                      @"Universal Typehandler Cell"];
            } else {
                cell = [tableView dequeueReusableCellWithIdentifier:@"Message Cell"];
            }
            // TOCK(init);

            for (UIView *subView in cell.subviews) {
                @autoreleasepool {
                    if ([subView isKindOfClass:[UILazyImageView class]]) {
                        [subView removeFromSuperview];
                    }
                    if ([subView isKindOfClass:[DCChatVideoAttachment class]]) {
                        [subView removeFromSuperview];
                    }
                    if ([subView isKindOfClass:[QLPreviewController class]]) {
                        [subView removeFromSuperview];
                    }
                }
            }
            for (UIView *subView in cell.contentTextView.subviews) {
                @autoreleasepool {
                    if ([subView isKindOfClass:[UIImageView class]]) { // emojis
                        [subView removeFromSuperview];
                    }
                }
            }

            if (messageAtRowIndex.referencedMessage != nil) {
                cell.referencedAuthorLabel.text = messageAtRowIndex.referencedMessage.author.globalName;
                cell.referencedMessage.text     = messageAtRowIndex.referencedMessage.content;
                cell.referencedMessage.frame    = CGRectMake(
                    messageAtRowIndex.referencedMessage
                        .authorNameWidth,
                    cell.referencedMessage.y,
                    self.chatTableView.width
                        - messageAtRowIndex.authorNameWidth,
                    cell.referencedMessage.height
                );

                cell.referencedProfileImage.image = messageAtRowIndex.referencedMessage.author
                                                        .profileImage;
                cell.referencedProfileImage.layer.cornerRadius =
                    cell.referencedProfileImage.frame.size.height / 2;
                cell.referencedProfileImage.layer.masksToBounds = YES;
                // UITapGestureRecognizer *singleTap =
                //     [[UITapGestureRecognizer alloc]
                //         initWithTarget:self
                //                 action:@selector(tappedReferencedMessage:)];
                // singleTap.numberOfTapsRequired                = 1;
                // singleTap.cancelsTouchesInView = YES;
                // cell.referencedMessage.userInteractionEnabled = YES;
                // cell.referencedAuthorLabel.userInteractionEnabled = YES;
                // cell.referencedProfileImage.userInteractionEnabled = YES;
                // [cell.referencedMessage addGestureRecognizer:singleTap];
                // [cell.referencedAuthorLabel addGestureRecognizer:singleTap];
                // [cell.referencedProfileImage addGestureRecognizer:singleTap];
                UIButton *referencedMessageButton = [UIButton buttonWithType:UIButtonTypeCustom];
                referencedMessageButton.frame = CGRectMake(cell.referencedProfileImage.x, 
                                                           cell.referencedMessage.y, 
                                                           cell.referencedMessage.x + cell.referencedMessage.width - cell.referencedProfileImage.x, 
                                                           cell.referencedMessage.height);
                referencedMessageButton.exclusiveTouch = YES;
                [referencedMessageButton addTarget:self
                                             action:@selector(tappedReferencedMessage:)
                                      forControlEvents:UIControlEventTouchUpInside];
                [cell addSubview:referencedMessageButton];
            }

            if (!messageAtRowIndex.isGrouped) {
                cell.authorLabel.text     = messageAtRowIndex.author.globalName;
                cell.timestampLabel.text  = messageAtRowIndex.prettyTimestamp;
                cell.timestampLabel.frame = CGRectMake(
                    messageAtRowIndex.authorNameWidth,
                    cell.timestampLabel.y,
                    self.chatTableView.width
                        - messageAtRowIndex.authorNameWidth,
                    cell.timestampLabel.height
                );
            }

            if (messageAtRowIndex.messageType == DCMessageTypeRecipientAdd || messageAtRowIndex.messageType == DCMessageTypeUserJoin) {
                cell.universalImageView.image = [UIImage imageNamed:@"U-Add"];
            } else if (messageAtRowIndex.messageType == DCMessageTypeRecipientRemove) {
                cell.universalImageView.image = [UIImage imageNamed:@"U-Remove"];
            } else if (messageAtRowIndex.messageType == DCMessageTypeChannelNameChange || messageAtRowIndex.messageType == DCMessageTypeChannelIconChange) {
                cell.universalImageView.image = [UIImage imageNamed:@"U-Pen"];
            } else if (messageAtRowIndex.messageType == DCMessageTypeChannelPinnedMessage) {
                cell.universalImageView.image = [UIImage imageNamed:@"U-Pin"];
            } else if (messageAtRowIndex.messageType == DCMessageTypeGuildBoost || messageAtRowIndex.messageType == DCMessageTypeThreadCreated) {
                cell.universalImageView.image = [UIImage imageNamed:@"U-Boost"];
            }

            if (VERSION_MIN(@"6.0")) {
                cell.contentTextView.attributedText = nil;
            }
            cell.contentTextView.text            = @"";
            cell.contentTextView.textColor       = [UIColor whiteColor];
            cell.contentTextView.font            = [UIFont fontWithName:@"HelveticaNeue" size:14];
            cell.contentTextView.backgroundColor = [UIColor clearColor];
            cell.contentTextView.textAlignment   = NSTextAlignmentLeft;

            // TICK(content);
            if (VERSION_MIN(@"6.0") && messageAtRowIndex.attributedContent) {
                cell.contentTextView.attributedText = messageAtRowIndex.attributedContent;
                [cell adjustTextViewSize];
            } else {
                cell.contentTextView.text = messageAtRowIndex.content;
            }

            // Emoji handling
            for (NSArray *emojiInfo in messageAtRowIndex.emojis) {
                DCEmoji *emoji        = emojiInfo[0];
                NSNumber *location    = emojiInfo[1];
                UITextPosition *start = [cell.contentTextView
                    positionFromPosition:cell.contentTextView.beginningOfDocument
                                  offset:location.unsignedIntegerValue];
                UITextPosition *end   = [cell.contentTextView
                    positionFromPosition:start
                                  offset:4];
                UITextRange *txtRange = [cell.contentTextView textRangeFromPosition:start toPosition:end];
                CGRect rect           = [cell.contentTextView firstRectForRange:txtRange];
                rect.origin.y += 1; // padding
                rect.size.width             = MAX(rect.size.width, 16);
                rect.size.height            = rect.size.width;
                UIImageView *emojiImageView = [[UIImageView alloc] initWithFrame:rect];
                emojiImageView.image        = emoji.image;
                emojiImageView.frame        = CGRectMake(
                    emojiImageView.frame.origin.x,
                    emojiImageView.frame.origin.y,
                    32 / [UIScreen mainScreen].scale,
                    32 / [UIScreen mainScreen].scale
                );
                [cell.contentTextView addSubview:emojiImageView];
            }
            // TOCK(content);

            double height = [cell.contentTextView
                                sizeThatFits:CGSizeMake(cell.contentTextView.width, MAXFLOAT)]
                                .height;
            cell.contentTextView.height = height;

            if (!messageAtRowIndex.isGrouped) {
                if (messageAtRowIndex.author.avatarDecoration &&
                    [messageAtRowIndex.author.avatarDecoration isKindOfClass:[UIImage class]]) {
                    cell.avatarDecoration.image        = messageAtRowIndex.author.avatarDecoration;
                    cell.avatarDecoration.layer.hidden = NO;
                    cell.avatarDecoration.opaque       = NO;
                } else {
                    cell.avatarDecoration.layer.hidden = YES;
                }
                cell.profileImage.image = messageAtRowIndex.author.profileImage;
                cell.profileImage.layer.cornerRadius =
                    cell.profileImage.frame.size.height / 2;
                cell.profileImage.layer.masksToBounds = YES;
            }

            if ((self.replyingToMessage
                 && [self.replyingToMessage.snowflake
                     isEqualToString:messageAtRowIndex.snowflake])
                || (self.editingMessage
                    && [self.editingMessage.snowflake
                        isEqualToString:messageAtRowIndex.snowflake])) {
                cell.contentView.backgroundColor =
                    [UIColor colorWithRed:55 / 255.0f
                                    green:59 / 255.0f
                                     blue:64 / 255.0f
                                    alpha:1.00f];
            } else if (messageAtRowIndex.pingingUser) {
                cell.contentView.backgroundColor =
                    [UIColor colorWithRed:46 / 255.0f
                                    green:45 / 255.0f
                                     blue:40 / 255.0f
                                    alpha:1.00f];
            } else {
                cell.contentView.backgroundColor = [UIColor clearColor];
            }

            cell.contentView.layer.cornerRadius  = 0;
            cell.contentView.layer.masksToBounds = YES;

            float contentWidth    = UIScreen.mainScreen.bounds.size.width - 63;
            CGSize authorNameSize = [messageAtRowIndex.author.globalName
                     sizeWithFont:[UIFont boldSystemFontOfSize:15]
                constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                    lineBreakMode:(NSLineBreakMode)UILineBreakModeWordWrap];

            // dispatch_async(dispatch_get_main_queue(), ^{
            CGFloat imageViewOffset = (!messageAtRowIndex.isGrouped
                                           ? authorNameSize.height
                                               + (messageAtRowIndex.referencedMessage != nil ? 16 : 0)
                                           : 0)
                + (
                                          [messageAtRowIndex.content length] != 0
                                              ? height
                                              : (!messageAtRowIndex.isGrouped ? 10 : 0) // ???
                );

            for (id attachment in messageAtRowIndex.attachments) {
                @autoreleasepool {
                    if ([attachment isKindOfClass:[UILazyImage class]]) {
                        UILazyImageView *imageView = [UILazyImageView new];
                        UILazyImage *lazyImage     = attachment;
                        CGFloat aspectRatio        = lazyImage.image.size.width / lazyImage.image.size.height;
                        int newWidth               = 200 * aspectRatio;
                        int newHeight              = 200;
                        if (newWidth > self.chatTableView.width - 66) {
                            newWidth  = self.chatTableView.width - 66;
                            newHeight = newWidth / aspectRatio;
                        }
                        imageView.frame = CGRectMake(
                            55, imageViewOffset, newWidth, newHeight
                        );
                        imageView.image    = lazyImage.image;
                        imageView.imageURL = lazyImage.imageURL;
                        imageViewOffset += newHeight;

                        imageView.contentMode = UIViewContentModeScaleAspectFit;

                        UITapGestureRecognizer *singleTap =
                            [[UITapGestureRecognizer alloc]
                                initWithTarget:self
                                        action:@selector(tappedImage:)];
                        singleTap.numberOfTapsRequired   = 1;
                        imageView.userInteractionEnabled = YES;

                        [imageView addGestureRecognizer:singleTap];

                        imageView.layer.cornerRadius  = 6;
                        imageView.layer.masksToBounds = YES;

                        [cell addSubview:imageView];
                    } else if ([attachment
                                   isKindOfClass:[DCChatVideoAttachment class]]) {
                        ////NSLog(@"add video!");
                        DCChatVideoAttachment *video = attachment;

                        UITapGestureRecognizer *singleTap =
                            [[UITapGestureRecognizer alloc]
                                initWithTarget:self
                                        action:@selector(tappedVideo:)];
                        singleTap.numberOfTapsRequired = 1;
                        [video.playButton addGestureRecognizer:singleTap];
                        video.playButton.userInteractionEnabled = YES;

                        CGFloat aspectRatio = video.thumbnail.image.size.width
                            / video.thumbnail.image.size.height;
                        int newWidth  = 200 * aspectRatio;
                        int newHeight = 200;
                        if (newWidth > self.chatTableView.width - 66) {
                            newWidth  = self.chatTableView.width - 66;
                            newHeight = newWidth / aspectRatio;
                        }
                        [video setFrame:CGRectMake(
                                            55, imageViewOffset, newWidth, newHeight
                                        )];

                        imageViewOffset += newHeight;

                        [cell addSubview:video];
                    } else if ([attachment isKindOfClass:[QLPreviewController class]]) {
                        ////NSLog(@"Add QuickLook!");
                        QLPreviewController *preview = attachment;

                        /*UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer
                         alloc] initWithTarget:self action:@selector(tappedVideo:)];
                         singleTap.numberOfTapsRequired = 1;
                         [video.playButton addGestureRecognizer:singleTap];
                         video.playButton.userInteractionEnabled = YES;

                         CGFloat aspectRatio = video.thumbnail.image.size.width /
                         video.thumbnail.image.size.height; int newWidth = 200 *
                         aspectRatio; int newHeight = 200; if (newWidth >
                         self.chatTableView.width - 66) { newWidth =
                         self.chatTableView.width - 66; newHeight = newWidth /
                         aspectRatio;
                         }
                         [video setFrame:CGRectMake(55, imageViewOffset, newWidth,
                         newHeight)];*/

                        imageViewOffset += 210;

                        [cell addSubview:preview.view];
                    } else if ([attachment isKindOfClass:[NSArray class]]) {
                        NSArray *dimensions = attachment;
                        if (dimensions.count == 2) {
                            int width  = [dimensions[0] intValue];
                            int height = [dimensions[1] intValue];
                            if (width <= 0 || height <= 0) {
                                continue;
                            }
                            CGFloat aspectRatio = (CGFloat)width / height;
                            int newWidth        = 200 * aspectRatio;
                            int newHeight       = 200;
                            if (newWidth > self.chatTableView.width - 66) {
                                newWidth  = self.chatTableView.width - 66;
                                newHeight = newWidth / aspectRatio;
                            }
                            UIActivityIndicatorView *activityIndicator =
                                [[UIActivityIndicatorView alloc]
                                    initWithActivityIndicatorStyle:
                                        UIActivityIndicatorViewStyleWhite];
                            [activityIndicator setFrame:CGRectMake(
                                                            55, imageViewOffset, newWidth,
                                                            newHeight
                                                        )];
                            [activityIndicator setContentMode:UIViewContentModeScaleAspectFit];
                            imageViewOffset += newHeight + 11;

                            [cell addSubview:activityIndicator];
                            [activityIndicator startAnimating];
                        }
                    }
                }
            }
        }
    }
    return cell;
}


- (CGFloat)tableView:(UITableView *)tableView
    heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    DCMessage *messageAtRowIndex = [self.messages objectAtIndex:indexPath.row];

    int attachmentHeight = 0;
    for (id attachment in messageAtRowIndex.attachments) {
        if ([attachment isKindOfClass:[UILazyImage class]]) {
            UIImage *image      = ((UILazyImage *)attachment).image;
            CGFloat aspectRatio = image.size.width / image.size.height;
            int newWidth        = 200 * aspectRatio;
            int newHeight       = 200;
            if (newWidth > self.chatTableView.width - 66) {
                newWidth  = self.chatTableView.width - 66;
                newHeight = newWidth / aspectRatio;
            }
            attachmentHeight += newHeight;
        } else if ([attachment isKindOfClass:[DCChatVideoAttachment class]]) {
            DCChatVideoAttachment *video = attachment;
            CGFloat aspectRatio          = video.thumbnail.image.size.width
                / video.thumbnail.image.size.height;
            int newWidth  = 200 * aspectRatio;
            int newHeight = 200;
            if (newWidth > self.chatTableView.width - 66) {
                newWidth  = self.chatTableView.width - 66;
                newHeight = newWidth / aspectRatio;
            }
            attachmentHeight += newHeight;
        } else if ([attachment isKindOfClass:[NSArray class]]) {
            NSArray *dimensions = attachment;
            if (dimensions.count == 2) {
                int width  = [dimensions[0] intValue];
                int height = [dimensions[1] intValue];
                if (width <= 0 || height <= 0) {
                    continue;
                }
                CGFloat aspectRatio = (CGFloat)width / height;
                int newWidth        = 200 * aspectRatio;
                int newHeight       = 200;
                if (newWidth > self.chatTableView.width - 66) {
                    newWidth  = self.chatTableView.width - 66;
                    newHeight = newWidth / aspectRatio;
                }
                attachmentHeight += newHeight;
            }
        }
    }
    return messageAtRowIndex.contentHeight
        + attachmentHeight
        + (attachmentHeight ? 11 : 0);
}


- (void)tableView:(UITableView *)tableView
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    self.selectedMessage = self.messages[indexPath.row];

    NSString *replyButton = self.replyingToMessage
            && [self.replyingToMessage.snowflake isEqualToString:self.selectedMessage.snowflake]
        ? @"Cancel Reply"
        : @"Reply";
    if ([self.selectedMessage.author.snowflake
            isEqualToString:DCServerCommunicator.sharedInstance.snowflake]) {
        NSString *editButton = self.editingMessage
                && [self.editingMessage.snowflake isEqualToString:self.selectedMessage.snowflake]
            ? @"Cancel Edit"
            : @"Edit";
        UIActionSheet *messageActionSheet =
            [[UIActionSheet alloc] initWithTitle:self.selectedMessage.content
                                        delegate:self
                               cancelButtonTitle:@"Cancel"
                          destructiveButtonTitle:@"Delete"
                               otherButtonTitles:editButton,
                                                 replyButton,
                                                 @"Copy Message ID",
                                                 @"View Profile",
                                                 nil];
        messageActionSheet.tag = 1;
        messageActionSheet.delegate = self;
        [messageActionSheet showFromToolbar:self.toolbar];
    } else {
        UIActionSheet *messageActionSheet = [[UIActionSheet alloc]
                     initWithTitle:self.selectedMessage.content
                          delegate:self
                 cancelButtonTitle:nil
            destructiveButtonTitle:nil
                 otherButtonTitles:nil];
        [messageActionSheet addButtonWithTitle:replyButton];
        if (self.replyingToMessage
            && [self.replyingToMessage.snowflake
                isEqualToString:self.selectedMessage.snowflake]) {
            [messageActionSheet addButtonWithTitle:self.disablePing ? @"Enable Ping" : @"Disable Ping"];
        }
        [messageActionSheet addButtonWithTitle:@"Mention"];
        [messageActionSheet addButtonWithTitle:@"Copy Message ID"];
        [messageActionSheet addButtonWithTitle:@"View Profile"];
        messageActionSheet.cancelButtonIndex = [messageActionSheet addButtonWithTitle:@"Cancel"];
        messageActionSheet.tag = 3;
        messageActionSheet.delegate = self;
        [messageActionSheet showFromToolbar:self.toolbar];
    }
}

- (void)actionSheet:(UIActionSheet *)popup
    clickedButtonAtIndex:(NSInteger)buttonIndex {
    if ([popup tag] == 1) {
        if (buttonIndex == 0) {
            [self.selectedMessage deleteMessage];
        } else if (buttonIndex == 1) {
            if (self.editingMessage
                && [self.editingMessage.snowflake
                    isEqualToString:self.selectedMessage.snowflake]) {
                self.editingMessage               = nil;
                self.inputField.text              = @"";
                self.inputFieldPlaceholder.hidden = NO;
            } else {
                self.editingMessage               = self.selectedMessage;
                self.inputField.text              = self.selectedMessage.content;
                self.inputFieldPlaceholder.hidden = YES;
            }
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self.messages indexOfObject:self.selectedMessage]
                                                        inSection:0];
            [self.chatTableView beginUpdates];
            [self.chatTableView reloadRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationNone];
            [self.chatTableView endUpdates];
        } else if (buttonIndex == 2) {
            self.replyingToMessage = !self.replyingToMessage
                    || ![self.replyingToMessage.snowflake isEqualToString:self.selectedMessage.snowflake]
                ? self.selectedMessage
                : nil;
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self.messages indexOfObject:self.selectedMessage]
                                                        inSection:0];
            [self.chatTableView beginUpdates];
            [self.chatTableView reloadRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationNone];
            [self.chatTableView endUpdates];
        } else if (buttonIndex == 3) {
            UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
            [pasteboard setString:self.selectedMessage.snowflake];
        } else if (buttonIndex == 4) {
            [self performSegueWithIdentifier:@"chat to contact" sender:self];
        }
    } else if ([popup tag] == 2) { // Image Source selection
        UIImagePickerController *picker = UIImagePickerController.new;
        // TODO: add video send function
        picker.mediaTypes = [UIImagePickerController
            availableMediaTypesForSourceType:
                UIImagePickerControllerSourceTypeCamera];
        // picker.videoQuality = UIImagePickerControllerQualityTypeLow;
        picker.delegate = (id)self;

        if (buttonIndex == 0) {
            if ([UIImagePickerController
                    isSourceTypeAvailable:
                        UIImagePickerControllerSourceTypeCamera]) {
                picker.sourceType = UIImagePickerControllerSourceTypeCamera;
            } else {
                ////NSLog(@"Camera not available on this device.");
                return;
            }
        } else if (buttonIndex == 1) {
            picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        } else {
            // Cancel tapped or another option (safe to ignore)
            return;
        }
        [picker viewWillAppear:YES];
        [self presentViewController:picker animated:YES completion:nil];
        [picker viewWillAppear:YES];
    } else if ([popup tag] == 3) {
        int addbut = self.replyingToMessage
                && [self.replyingToMessage.snowflake isEqualToString:self.selectedMessage.snowflake]
            ? 1
            : 0;
        if (buttonIndex == 0) { // (cancel) reply
            self.replyingToMessage = !self.replyingToMessage
                    || ![self.replyingToMessage.snowflake isEqualToString:self.selectedMessage.snowflake]
                ? self.selectedMessage
                : nil;
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self.messages indexOfObject:self.selectedMessage]
                                                        inSection:0];
            [self.chatTableView beginUpdates];
            [self.chatTableView reloadRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationNone];
            [self.chatTableView endUpdates];
        } else if (buttonIndex == addbut) { // will never match when 0
            self.disablePing = !self.disablePing;
        } else if (buttonIndex == 1 + addbut) {
            self.inputField.text = [NSString
                stringWithFormat:@"%@<@%@> ", self.inputField.text,
                                 self.selectedMessage.author.snowflake];
        } else if (buttonIndex == 2 + addbut) {
            UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
            [pasteboard setString:self.selectedMessage.snowflake];
        } else if (buttonIndex == 3 + addbut) {
            [self performSegueWithIdentifier:@"chat to contact" sender:self];
        }
    }
}


- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    self.viewingPresentTime =
        (scrollView.contentOffset.y
         >= scrollView.contentSize.height - scrollView.height - 10);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView
    numberOfRowsInSection:(NSInteger)section {
    return [self.messages count];
}

- (void)keyboardWillShow:(NSNotification *)notification {
    // thx to Pierre Legrain
    // http://pyl.io/2015/08/17/animating-in-sync-with-ios-keyboard/
    self.keyboardHeight =
        [[notification.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey]
            CGRectValue]
            .size.height;
    float keyboardAnimationDuration = [[notification.userInfo
        objectForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue];
    int keyboardAnimationCurve      = [[notification.userInfo
        objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue];

    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:keyboardAnimationDuration];
    [UIView setAnimationCurve:keyboardAnimationCurve];
    [UIView setAnimationBeginsFromCurrentState:YES];
    [self.chatTableView
        setHeight:self.view.height - self.keyboardHeight - self.toolbar.height - (self.typingUsers.count > 0 ? 20 : 0)];
    if (self.typingUsers.count > 0) {
        [self.typingIndicatorView setY:self.view.height - self.keyboardHeight - self.toolbar.height - 20];
    }
    [self.toolbar setY:self.view.height - self.keyboardHeight - self.toolbar.height];
    [UIView commitAnimations];

    if (self.viewingPresentTime) {
        [self.chatTableView
            setContentOffset:CGPointMake(
                                 0,
                                 self.chatTableView.contentSize.height
                                     - self.chatTableView.frame.size.height
                             )
                    animated:NO];
    }
}


- (void)keyboardWillHide:(NSNotification *)notification {
    self.keyboardHeight             = 0;
    float keyboardAnimationDuration = [[notification.userInfo
        objectForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue];
    int keyboardAnimationCurve      = [[notification.userInfo
        objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue];

    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:keyboardAnimationDuration];
    [UIView setAnimationCurve:keyboardAnimationCurve];
    [UIView setAnimationBeginsFromCurrentState:YES];
    [self.chatTableView setHeight:self.view.height - self.toolbar.height - (self.typingUsers.count > 0 ? 20 : 0)];
    if (self.typingUsers.count > 0) {
        [self.typingIndicatorView setY:self.view.height - self.toolbar.height - 20];
    }
    [self.toolbar setY:self.view.height - self.toolbar.height];
    [UIView commitAnimations];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view.superview isKindOfClass:[UIToolbar class]];
}

- (void)dismissKeyboard:(UITapGestureRecognizer *)sender {
    [self.view endEditing:YES];

    NSDictionary *userInfo = @{
        UIKeyboardAnimationDurationUserInfoKey : @(0.25),
        UIKeyboardAnimationCurveUserInfoKey : @(UIViewAnimationCurveEaseInOut),
        UIKeyboardFrameBeginUserInfoKey : [NSValue valueWithCGRect:CGRectZero],
        UIKeyboardFrameEndUserInfoKey : [NSValue valueWithCGRect:CGRectZero],
    };

    [[NSNotificationCenter defaultCenter]
        postNotificationName:UIKeyboardWillHideNotification
                      object:nil
                    userInfo:userInfo];
}

- (IBAction)sendMessage:(id)sender {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self.inputField.text isEqual:@""]) {
            NSString *msg = [DCTools parseMessage:self.inputField.text
                                        withGuild:DCServerCommunicator.sharedInstance.selectedChannel.parentGuild];
            if (self.editingMessage) {
                [DCServerCommunicator.sharedInstance.selectedChannel
                    editMessage:self.editingMessage
                    withContent:msg];
            } else {
                [DCServerCommunicator.sharedInstance.selectedChannel
                           sendMessage:msg
                    referencingMessage:self.replyingToMessage ? self.replyingToMessage : nil
                           disablePing:self.disablePing];
            }
            if (self.replyingToMessage || self.editingMessage) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self.messages
                                                                          indexOfObject:self.replyingToMessage
                                                                              ? self.replyingToMessage
                                                                              : self.editingMessage]
                                                            inSection:0];
                self.replyingToMessage = nil;
                self.editingMessage    = nil;
                [self.chatTableView beginUpdates];
                [self.chatTableView reloadRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationNone];
                [self.chatTableView endUpdates];
            }
            self.disablePing = NO;
            [self.inputField setText:@""];
            self.inputFieldPlaceholder.hidden = NO;
            lastTimeInterval                  = 0;
        } else {
            [self.inputField resignFirstResponder];
        }

        [self.chatTableView
            setContentOffset:CGPointMake(
                                 0,
                                 self.chatTableView.contentSize.height
                                     - self.chatTableView.frame.size.height
                             )
                    animated:YES];
    });
}

- (void)tappedReferencedMessage:(UIButton *)sender {
    assertMainThread();
    [self.inputField resignFirstResponder];
    CGPoint buttonPosition = [sender convertPoint:CGPointZero toView:self.chatTableView];
    NSIndexPath *indexPath = [self.chatTableView indexPathForRowAtPoint:buttonPosition];
    if (!indexPath) {
        DBGLOG(@"Tapped referenced message, but indexPath is nil!");
        return;
    }
    DCMessage *messageAtRowIndex = [self.messages objectAtIndex:indexPath.row];
    if (!messageAtRowIndex.referencedMessage) {
        DBGLOG(@"Tapped referenced message, but referencedMessage is nil!");
        return;
    }
    // scroll to referenced message
    NSUInteger referencedMessageIndex = [self.messages indexOfObjectPassingTest:^BOOL(DCMessage *obj, NSUInteger idx, BOOL *stop) {
        return [obj.snowflake isEqualToString:messageAtRowIndex.referencedMessage.snowflake];
    }];
    if (referencedMessageIndex == NSNotFound) {
        DBGLOG(@"Referenced message not found in messages array!");
        return;
    }
    [self.chatTableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:referencedMessageIndex inSection:0]
                                  atScrollPosition:UITableViewScrollPositionMiddle
                                          animated:YES];
}

- (void)tappedImage:(UITapGestureRecognizer *)sender {
    assertMainThread();
    [self.inputField resignFirstResponder];
    SDWebImageManager *manager = [SDWebImageManager sharedManager];
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication.sharedApplication setNetworkActivityIndicatorVisible:YES];
    });
    [manager downloadImageWithURL:((UILazyImageView *)sender.view).imageURL
                          options:0
                         progress:nil
                        completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [UIApplication.sharedApplication setNetworkActivityIndicatorVisible:NO];
                            });
                            if (image) {
                                self.selectedImage = image;
                                [self performSegueWithIdentifier:@"Chat to Gallery" sender:self];
                            }
                        }];
}

- (void)tappedVideo:(UITapGestureRecognizer *)sender {
    assertMainThread();
    [self.inputField resignFirstResponder];
    DBGLOG(@"Tapped video!");
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *url                          = ((DCChatVideoAttachment *)sender.view.superview).videoURL;
        MPMoviePlayerViewController *player = [[MPMoviePlayerViewController alloc] initWithContentURL:url];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(moviePlaybackDidFinish:)
                                                     name:MPMoviePlayerPlaybackDidFinishNotification
                                                   object:player.moviePlayer];
        player.moviePlayer.repeatMode = MPMovieRepeatModeOne;
        UIWindow *backgroundWindow    = [UIApplication sharedApplication].keyWindow;
        player.view.frame             = backgroundWindow.frame;
        //[self.view addSubview:player.moviePlayer.view];
        [self presentMoviePlayerViewControllerAnimated:player];
        [player.moviePlayer play];
    });
}

- (void)moviePlaybackDidFinish:(NSNotification *)notification {
    NSNumber *reason = notification.userInfo[MPMoviePlayerPlaybackDidFinishReasonUserInfoKey];

    if ([reason intValue] == MPMovieFinishReasonPlaybackError) {
        NSError *error = notification.userInfo[@"error"];
        NSLog(@"Playback error occurred: %@", error);
    } else if ([reason intValue] == MPMovieFinishReasonUserExited) {
        DBGLOG(@"User exited playback");
    } else if ([reason intValue] == MPMovieFinishReasonPlaybackEnded) {
        DBGLOG(@"Playback ended normally");
    }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"Chat to Gallery"]) {
        DCImageViewController *imageViewController =
            [segue destinationViewController];

        if ([imageViewController isKindOfClass:[DCImageViewController class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [imageViewController.imageView setImage:self.selectedImage];
            });
        }
    } else if ([segue.identifier isEqualToString:@"Chat to Right Sidebar"]) {
        DCCInfoViewController *rightSidebar = [segue destinationViewController];

        if ([rightSidebar isKindOfClass:[DCCInfoViewController class]]) {
            [rightSidebar.navigationItem setTitle:self.navigationItem.title];
        }
    }

    if ([segue.destinationViewController isKindOfClass:[DCContactViewController class]]) {
        [((DCContactViewController *)segue.destinationViewController)
            setSelectedUser:self.selectedMessage.author];
    } else if ([segue.destinationViewController isKindOfClass:[ODCContactViewController class]]) {
        [((ODCContactViewController *)segue.destinationViewController)
            setSelectedUser:self.selectedMessage.author];
    }
}

- (IBAction)openSidebar:(id)sender {
    [self.slideMenuController showLeftMenu:YES];
}
- (IBAction)clickMemberButton:(id)sender {
    [self.slideMenuController showRightMenu:YES];
}

- (IBAction)chooseImage:(id)sender {
    [self.inputField resignFirstResponder];

    if ([UIDevice currentDevice].userInterfaceIdiom
        == UIUserInterfaceIdiomPad) {
        // iPad-specific implementation using UIPopoverController
        if ([UIImagePickerController
                isSourceTypeAvailable:
                    UIImagePickerControllerSourceTypePhotoLibrary]) {
            UIImagePickerController *picker = UIImagePickerController.new;
            picker.sourceType               = UIImagePickerControllerSourceTypePhotoLibrary;
            picker.delegate                 = self;

            // Initialize UIPopoverController
            UIPopoverController *popoverController =
                [[UIPopoverController alloc]
                    initWithContentViewController:picker];
            self.imagePopoverController = popoverController;

            if ([sender isKindOfClass:[UIBarButtonItem class]]) {
                // Use the bar button item's view for popover presentation
                UIBarButtonItem *barButtonItem = (UIBarButtonItem *)sender;
                [popoverController
                    presentPopoverFromBarButtonItem:barButtonItem
                           permittedArrowDirections:UIPopoverArrowDirectionAny
                                           animated:YES];
            }
        }
    } else {
        if ([UIImagePickerController
                isSourceTypeAvailable:
                    UIImagePickerControllerSourceTypeCamera]) {
            UIActionSheet *imageSourceActionSheet =
                [[UIActionSheet alloc] initWithTitle:nil
                                            delegate:self
                                   cancelButtonTitle:@"Cancel"
                              destructiveButtonTitle:nil
                                   otherButtonTitles:@"Take Photo or Video",
                                                     @"Choose Existing", nil];
            [imageSourceActionSheet setTag:2];
            [imageSourceActionSheet showFromToolbar:self.toolbar];
        } else {
            // Camera is not supported, use photo library
            UIImagePickerController *picker = UIImagePickerController.new;
            picker.sourceType               = UIImagePickerControllerSourceTypePhotoLibrary;
            picker.delegate                 = self;

            [self presentViewController:picker animated:YES completion:nil];
        }
    }
}

- (void)imagePickerController:(UIImagePickerController *)picker
    didFinishPickingMediaWithInfo:(NSDictionary *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    [self.imagePopoverController dismissPopoverAnimated:YES];
    self.imagePopoverController = nil;

    NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];

    if ([mediaType isEqualToString:@"public.movie"]) { // Check if it's a video
        NSURL *videoURL     = [info objectForKey:UIImagePickerControllerMediaURL];
        NSString *extension = [videoURL pathExtension];

        NSString *mimeType;
        if ([extension caseInsensitiveCompare:@"mov"] == NSOrderedSame) {
            mimeType = @"video/mov";
        } else if ([extension caseInsensitiveCompare:@"mp4"] == NSOrderedSame) {
            mimeType = @"video/mp4";
        } else {
            ////NSLog(@"Unsupported video format: %@", extension);
            return;
        }

        ////NSLog(@"MIME type %@", mimeType);

        // Use the sendVideo:mimeType: function to send the video
        [DCServerCommunicator.sharedInstance.selectedChannel
            sendVideo:videoURL
             mimeType:mimeType];

    } else if ([mediaType
                   isEqualToString:@"public.image"]) { // Check if it's an image
        UIImage *originalImage =
            [info objectForKey:UIImagePickerControllerEditedImage];
        if (!originalImage) {
            originalImage =
                [info objectForKey:UIImagePickerControllerOriginalImage];
        }
        if (!originalImage) {
            originalImage = [info objectForKey:UIImagePickerControllerCropRect];
        }

        // Determine the MIME type for the image based on the data
        NSString *mimeType = @"image/jpeg";

        NSString *extension =
            [info[UIImagePickerControllerReferenceURL] pathExtension];
        if ([extension caseInsensitiveCompare:@"png"] == NSOrderedSame) {
            mimeType = @"image/png";
        } else if ([extension caseInsensitiveCompare:@"gif"] == NSOrderedSame) {
            mimeType = @"image/gif";
        }
        if ([mimeType isEqualToString:@"image/gif"]) {
            ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
            [library assetForURL:
                         [info objectForKey:UIImagePickerControllerReferenceURL]
                     resultBlock:^(ALAsset *asset) {
                         ALAssetRepresentation *representation =
                             [asset defaultRepresentation];

                         Byte *buffer =
                             (Byte *)malloc((NSUInteger)representation.size);
                         NSUInteger buffered = [representation
                               getBytes:buffer
                             fromOffset:0
                                 length:(NSUInteger)representation.size
                                  error:nil];
                         NSData *data        = [NSData dataWithBytesNoCopy:buffer
                                                             length:buffered
                                                       freeWhenDone:YES];

                         [DCServerCommunicator.sharedInstance.selectedChannel
                             sendData:data
                             mimeType:mimeType];
                     }
                    failureBlock:^(NSError *error){
                        ////NSLog(@"couldn't get asset: %@", error);

                    }];

        } else {
            [DCServerCommunicator.sharedInstance.selectedChannel
                sendImage:originalImage
                 mimeType:mimeType];
        }
    }
}

- (IBAction)dismissModalPVTONLY:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)get50MoreMessages:(UIRefreshControl *)control {
    assertMainThread();
    if (self.messages == nil || self.messages.count == 0) {
        [control endRefreshing];
        return;
    }

    // dispatch_queue_t apiQueue = dispatch_queue_create([[NSString
    // stringWithFormat:@"Discord::API::Receive::getMessages%i",
    // arc4random_uniform(4)] UTF8String], NULL); dispatch_async(apiQueue, ^{
    [self getMessages:50 beforeMessage:[self.messages objectAtIndex:0]];
    //});
    // dispatch_release(apiQueue);
}
@end
