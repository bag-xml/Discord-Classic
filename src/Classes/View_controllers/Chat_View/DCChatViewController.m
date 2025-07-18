//
//  DCChatViewController.m
//  Discord Classic
//
//  Created by bag.xml on 3/6/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import "DCChatViewController.h"
#include <UIKit/UIKit.h>
#include <Foundation/NSObjCRuntime.h>
#include <objc/NSObjCRuntime.h>
#include <Foundation/Foundation.h>
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

@interface DCChatViewController ()
@property(nonatomic, strong) NSMutableArray *messages;
@property(nonatomic, assign) int numberOfMessagesLoaded;
@property(nonatomic, strong) UIImage *selectedImage;
@property(nonatomic, assign) BOOL oldMode;
@property(nonatomic, strong) UIRefreshControl *refreshControl;
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

    UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc] 
        initWithTarget:self
        action:@selector(dismissKeyboard:)];
    [self.view addGestureRecognizer:gestureRecognizer];
    gestureRecognizer.cancelsTouchesInView = NO;

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

    [self.inputField setDelegate:self];
    self.inputFieldPlaceholder.text = DCServerCommunicator.sharedInstance.selectedChannel.writeable
        ? [NSString stringWithFormat:@"Message%@%@", 
            ![DCServerCommunicator.sharedInstance.selectedChannel.parentGuild.name isEqualToString:@"Direct Messages"] 
            ? @" #" 
            : (DCServerCommunicator.sharedInstance.selectedChannel.recipients.count > 2 ? @" " : @" @"), 
            DCServerCommunicator.sharedInstance.selectedChannel.name]
        : @"No Permission";
    self.toolbar.userInteractionEnabled = DCServerCommunicator.sharedInstance.selectedChannel.writeable;
    self.inputFieldPlaceholder.hidden = NO;
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
    NSLog(@"%s: Resetting chat data", __PRETTY_FUNCTION__);
    self.messages = NSMutableArray.new;
    self.inputFieldPlaceholder.text = DCServerCommunicator.sharedInstance.selectedChannel.writeable
        ? [NSString stringWithFormat:@"Message%@%@", 
            ![DCServerCommunicator.sharedInstance.selectedChannel.parentGuild.name isEqualToString:@"Direct Messages"] 
            ? @" #" 
            : (DCServerCommunicator.sharedInstance.selectedChannel.recipients.count > 2 ? @" " : @" @"), 
            DCServerCommunicator.sharedInstance.selectedChannel.name]
        : @"No Permission";
    self.toolbar.userInteractionEnabled = DCServerCommunicator.sharedInstance.selectedChannel.writeable;
    [self handleAsyncReload];
}

- (void)handleAsyncReload {
    if (!self.chatTableView) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        //NSLog(@"async reload!");
        // about contact CoreControl

        [self.chatTableView reloadData];
    });
}

- (void)handleReady {
    if (DCServerCommunicator.sharedInstance.selectedChannel) {
        self.messages = NSMutableArray.new;
        self.inputFieldPlaceholder.text = DCServerCommunicator.sharedInstance.selectedChannel.writeable
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

- (void)handleReloadUser:(NSNotification *)notification {
    if (!self.chatTableView) {
        return;
    }

    NSInteger rowCount = [self.chatTableView numberOfRowsInSection:0];
    if (rowCount != self.messages.count) {
        NSLog(@"%s: Row count mismatch!", __PRETTY_FUNCTION__);
        [self handleAsyncReload];
        return;
    }

    DCUser *user = notification.object;
    NSMutableArray *indexPaths = NSMutableArray.new;
    for (int i = 0; i < self.messages.count; i++) {
        DCMessage *message = [self.messages objectAtIndex:i];
        if ([message.author.snowflake isEqualToString:user.snowflake]) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:0];
            [indexPaths addObject:indexPath];
        }
    }
    [self.chatTableView beginUpdates];
    [self.chatTableView reloadRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
    [self.chatTableView endUpdates];
}

- (void)handleReloadMessage:(NSNotification *)notification {
    if (!self.chatTableView) {
        return;
    }

    NSInteger rowCount = [self.chatTableView numberOfRowsInSection:0];
    if (rowCount != self.messages.count) {
        NSLog(@"%s: Row count mismatch!", __PRETTY_FUNCTION__);
        [self handleAsyncReload];
        return;
    }

    DCMessage *message = notification.object;
    NSUInteger index = [self.messages indexOfObject:message];
    if (index == NSNotFound || index >= self.messages.count) {
        return;
    }
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
    [self.chatTableView beginUpdates];
    [self.chatTableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self.chatTableView endUpdates];
}

- (void)handleMessageCreate:(NSNotification *)notification {
    // dispatch_async(dispatch_get_main_queue(), ^{
    DCMessage *newMessage = [DCTools convertJsonMessage:notification.userInfo];

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
                && (prevMessage.messageType == DEFAULT || prevMessage.messageType == REPLY)) {
                newMessage.isGrouped = (newMessage.messageType == DEFAULT || newMessage.messageType == REPLY) && (newMessage.referencedMessage == nil);

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
    if (rowCount != self.messages.count) {
        NSLog(@"%s: Row count mismatch!", __PRETTY_FUNCTION__);
        [self.messages addObject:newMessage];
        [self handleAsyncReload];
    } else {
        [self.chatTableView beginUpdates];
        [self.messages addObject:newMessage];
        NSIndexPath *newIndexPath = [NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0];
        [self.chatTableView insertRowsAtIndexPaths:@[newIndexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        [self.chatTableView endUpdates];
    }

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

- (void)handleMessageEdit:(NSNotification *)notification {
    NSString *snowflake       = [notification.userInfo objectForKey:@"id"];
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
    if (newMessage.author == nil || (NSNull*)newMessage.author == [NSNull null]) {
        newMessage.author = compareMessage.author;
        newMessage.contentHeight +=
            compareMessage.contentHeight; // assume it's an embed update
    }
    if (newMessage.content == nil || (NSNull*)newMessage.content == [NSNull null]) {
        newMessage.content = compareMessage.content;
    }
    if ((newMessage.attachments == nil || (NSNull*)newMessage.attachments == [NSNull null])
        && newMessage.attachmentCount > 0) {
        newMessage.attachments = compareMessage.attachments;
    }
    newMessage.timestamp = compareMessage.timestamp;
    if (newMessage.editedTimestamp == nil
        || (NSNull*)newMessage.editedTimestamp == [NSNull null]) {
        newMessage.editedTimestamp = compareMessage.editedTimestamp;
    }
    newMessage.prettyTimestamp   = compareMessage.prettyTimestamp;
    newMessage.referencedMessage = compareMessage.referencedMessage;

    if (self.messages.count > 0) {
        DCMessage *prevMessage = [self.messages
            objectAtIndex:[self.messages indexOfObject:compareMessage] - 1];
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
                && (prevMessage.messageType == DEFAULT || prevMessage.messageType == REPLY)) {
                newMessage.isGrouped = (newMessage.messageType == DEFAULT || newMessage.messageType == REPLY) && (newMessage.referencedMessage == nil);

                if (newMessage.isGrouped) {
                    float contentWidth =
                        UIScreen.mainScreen.bounds.size.width - 63;
                    CGSize authorNameSize = [newMessage.author.globalName
                             sizeWithFont:[UIFont boldSystemFontOfSize:15]
                        constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                            lineBreakMode:(NSLineBreakMode
                                          )UILineBreakModeWordWrap];

                    newMessage.contentHeight -= authorNameSize.height + 4;
                }
            }
        }
    }

    NSInteger rowCount = [self.chatTableView numberOfRowsInSection:0];
    NSUInteger idx = [self.messages indexOfObject:compareMessage];
    if (rowCount != self.messages.count) {
        NSLog(@"%s: Row count mismatch!", __PRETTY_FUNCTION__);
        [self.messages replaceObjectAtIndex:idx
                             withObject:newMessage];
        [self handleAsyncReload];
        return;
    }
    [self.chatTableView beginUpdates];
    [self.messages replaceObjectAtIndex:idx
                             withObject:newMessage];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:idx inSection:0];
    [self.chatTableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self.chatTableView endUpdates];
}

- (void)handleMessageDelete:(NSNotification *)notification {
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
        NSLog(@"%s: Row count mismatch!", __PRETTY_FUNCTION__);
        [self.messages removeObjectAtIndex:index];
        [self handleAsyncReload];
    } else {
        [self.chatTableView beginUpdates];
        [self.messages removeObjectAtIndex:index];
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
        [self.chatTableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
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
        && (prevMessage.messageType == DEFAULT || prevMessage.messageType == REPLY)) {
        Boolean oldGroupedFlag = newMessage.isGrouped;
        newMessage.isGrouped   = (newMessage.messageType == DEFAULT || newMessage.messageType == REPLY) && (newMessage.referencedMessage == nil);

        if (newMessage.isGrouped
            && (newMessage.isGrouped != oldGroupedFlag)) {
            float contentWidth =
                UIScreen.mainScreen.bounds.size.width - 63;
            CGSize authorNameSize = [newMessage.author.globalName
                     sizeWithFont:[UIFont boldSystemFontOfSize:15]
                constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                    lineBreakMode:(NSLineBreakMode
                                  )UILineBreakModeWordWrap];

            newMessage.contentHeight -= authorNameSize.height + 4;
        }
    } else if (newMessage.isGrouped) {
        newMessage.isGrouped = false;
        float contentWidth =
            UIScreen.mainScreen.bounds.size.width - 63;
        CGSize authorNameSize = [newMessage.author.globalName
                 sizeWithFont:[UIFont boldSystemFontOfSize:15]
            constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                lineBreakMode:(NSLineBreakMode
                              )UILineBreakModeWordWrap];
        newMessage.contentHeight += authorNameSize.height + 4;
    }
}


- (void)getMessages:(int)numberOfMessages beforeMessage:(DCMessage *)message {
    dispatch_async([self get_chat_messages_queue], ^{
        NSArray *newMessages =
            [DCServerCommunicator.sharedInstance.selectedChannel
                  getMessages:numberOfMessages
                beforeMessage:message];

        if (newMessages) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSRange range = NSMakeRange(0, [newMessages count]);
                NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:range];

                NSInteger rowCount = [self.chatTableView numberOfRowsInSection:0];
                if (rowCount != self.messages.count) {
                    NSLog(@"%s: Row count mismatch!", __PRETTY_FUNCTION__);
                    [self.messages insertObjects:newMessages atIndexes:indexSet];
                    [self handleAsyncReload];
                } else {
                    NSMutableArray *indexPaths = [[NSMutableArray alloc] init];
                    [indexSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
                        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:idx inSection:0];
                        [indexPaths addObject:indexPath];
                    }];
                    [self.chatTableView beginUpdates];
                    [self.messages insertObjects:newMessages atIndexes:indexSet];
                    [self.chatTableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
                    [self.chatTableView endUpdates];
                }

                int scrollOffset = -self.chatTableView.height;
                for (DCMessage *newMessage in newMessages) {
                    int attachmentHeight = 0;
                    for (id attachment in newMessage.attachments) {
                        if ([attachment isKindOfClass:[UIImage class]]) {
                            UIImage *image      = attachment;
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
                        }
                    }
                    scrollOffset += newMessage.contentHeight
                        + attachmentHeight
                        + (attachmentHeight ? 11 : 0);
                }

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
        }
    });
}


- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DCChatTableCell *cell;

    if (!self.messages || [self.messages count] <= indexPath.row) {
        NSCAssert(self.messages, @"Messages array is nil");
        NSCAssert([self.messages count] > indexPath.row, @"Invalid indexPath");
    }
    DCMessage *messageAtRowIndex = [self.messages objectAtIndex:indexPath.row];

    if (self.oldMode == YES) {
        [tableView registerNib:[UINib nibWithNibName:@"O-DCChatTableCell"
                                              bundle:nil]
            forCellReuseIdentifier:@"OldMode Message Cell"];
        [tableView registerNib:[UINib nibWithNibName:@"O-DCChatGroupedTableCell"
                                              bundle:nil]
            forCellReuseIdentifier:@"OldMode Grouped Message Cell"];
        [tableView registerNib:[UINib nibWithNibName:@"O-DCChatReplyTableCell"
                                              bundle:nil]
            forCellReuseIdentifier:@"OldMode Reply Message Cell"];
        [tableView registerNib:[UINib nibWithNibName:@"O-DCUniversalTableCell"
                                              bundle:nil]
            forCellReuseIdentifier:@"OldMode Universal Typehandler Cell"];
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
            [cell.referencedAuthorLabel
                setText:messageAtRowIndex.referencedMessage.author.globalName];
            [cell.referencedMessage
                setText:messageAtRowIndex.referencedMessage.content];
            [cell.referencedMessage
                setFrame:CGRectMake(
                             messageAtRowIndex.referencedMessage
                                 .authorNameWidth,
                             cell.referencedMessage.y,
                             self.chatTableView.width
                                 - messageAtRowIndex.authorNameWidth,
                             cell.referencedMessage.height
                         )];

            [cell.referencedProfileImage
                setImage:messageAtRowIndex.referencedMessage.author
                             .profileImage];
        }

        if (!messageAtRowIndex.isGrouped) {
            [cell.authorLabel setText:messageAtRowIndex.author.globalName];
        }

        [cell.contentTextView setText:messageAtRowIndex.content];

        [cell.contentTextView
            setHeight:[cell.contentTextView
                          sizeThatFits:CGSizeMake(
                                           cell.contentTextView.width, MAXFLOAT
                                       )]
                          .height];

        if (!messageAtRowIndex.isGrouped) {
            [cell.profileImage setImage:messageAtRowIndex.author.profileImage];
        }

        [cell.contentView setBackgroundColor:messageAtRowIndex.pingingUser
                              ? [UIColor redColor]
                              : [UIColor clearColor]];

        for (UIView *subView in cell.subviews) {
            if ([subView isKindOfClass:[UIImageView class]]) {
                [subView removeFromSuperview];
            }
            if ([subView isKindOfClass:[DCChatVideoAttachment class]]) {
                [subView removeFromSuperview];
            }
            if ([subView isKindOfClass:[QLPreviewController class]]) {
                [subView removeFromSuperview];
            }
        }
        // dispatch_async(dispatch_get_main_queue(), ^{
        int imageViewOffset = cell.contentTextView.height + 37;

        for (id attachment in messageAtRowIndex.attachments) {
            if ([attachment isKindOfClass:[UIImage class]]) {
                UIImageView *imageView = UIImageView.new;
                [imageView setFrame:CGRectMake(
                                        11, imageViewOffset,
                                        self.chatTableView.width - 22, 200
                                    )];
                [imageView setImage:attachment];
                [imageView setContentMode:UIViewContentModeScaleAspectFit];

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
            }
        }
        return cell;
    } else if (self.oldMode == NO) {
        [tableView registerNib:[UINib nibWithNibName:@"DCChatGroupedTableCell"
                                              bundle:nil]
            forCellReuseIdentifier:@"Grouped Message Cell"];
        [tableView registerNib:[UINib nibWithNibName:@"DCChatTableCell"
                                              bundle:nil]
            forCellReuseIdentifier:@"Message Cell"];
        [tableView registerNib:[UINib nibWithNibName:@"DCChatReplyTableCell"
                                              bundle:nil]
            forCellReuseIdentifier:@"Reply Message Cell"];
        [tableView registerNib:[UINib nibWithNibName:@"DCUniversalTableCell"
                                              bundle:nil]
            forCellReuseIdentifier:@"Universal Typehandler Cell"];

        NSSet *specialMessageTypes =
            [NSSet setWithArray:@[ @1, @2, @3, @4, @5, @6, @7, @8, @18 ]];

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
            cell =
                [tableView dequeueReusableCellWithIdentifier:@"Message Cell"];
        }


        if (messageAtRowIndex.referencedMessage != nil) {
            [cell.referencedAuthorLabel
                setText:messageAtRowIndex.referencedMessage.author.globalName];
            [cell.referencedMessage
                setText:messageAtRowIndex.referencedMessage.content];
            [cell.referencedMessage
                setFrame:CGRectMake(
                             messageAtRowIndex.referencedMessage
                                 .authorNameWidth,
                             cell.referencedMessage.y,
                             self.chatTableView.width
                                 - messageAtRowIndex.authorNameWidth,
                             cell.referencedMessage.height
                         )];

            [cell.referencedProfileImage
                setImage:messageAtRowIndex.referencedMessage.author
                             .profileImage];
            cell.referencedProfileImage.layer.cornerRadius =
                cell.referencedProfileImage.frame.size.height / 2;
            cell.referencedProfileImage.layer.masksToBounds = YES;
        }

        if (!messageAtRowIndex.isGrouped) {
            [cell.authorLabel setText:messageAtRowIndex.author.globalName];
            [cell.timestampLabel setText:messageAtRowIndex.prettyTimestamp];
            [cell.timestampLabel
                setFrame:CGRectMake(
                             messageAtRowIndex.authorNameWidth,
                             cell.timestampLabel.y,
                             self.chatTableView.width
                                 - messageAtRowIndex.authorNameWidth,
                             cell.timestampLabel.height
                         )];
        }

        if (messageAtRowIndex.messageType == 1 || messageAtRowIndex.messageType == 7) {
            cell.universalImageView.image = [UIImage imageNamed:@"U-Add"];
        } else if (messageAtRowIndex.messageType == 2) {
            cell.universalImageView.image = [UIImage imageNamed:@"U-Remove"];
        } else if (messageAtRowIndex.messageType == 4 || messageAtRowIndex.messageType == 5) {
            cell.universalImageView.image = [UIImage imageNamed:@"U-Pen"];
        } else if (messageAtRowIndex.messageType == 6) {
            cell.universalImageView.image = [UIImage imageNamed:@"U-Pin"];
        } else if (messageAtRowIndex.messageType == 8 || messageAtRowIndex.messageType == 18) {
            cell.universalImageView.image = [UIImage imageNamed:@"U-Boost"];
        }

        if (VERSION_MIN(@"6.0")) {
            [cell configureWithMessage:messageAtRowIndex.content];
        } else {
            [cell.contentTextView setText:messageAtRowIndex.content];
        }

        double height = [cell.contentTextView
                            sizeThatFits:CGSizeMake(cell.contentTextView.width, MAXFLOAT)]
                            .height;
        [cell.contentTextView setHeight:height];

        if (!messageAtRowIndex.isGrouped) {
            if (messageAtRowIndex.author.avatarDecoration &&
                [messageAtRowIndex.author.avatarDecoration class] ==
                    [UIImage class]) {
                [cell.avatarDecoration
                    setImage:messageAtRowIndex.author.avatarDecoration];
                cell.avatarDecoration.layer.hidden = NO;
                cell.avatarDecoration.opaque       = NO;
            } else {
                cell.avatarDecoration.layer.hidden = YES;
            }
            [cell.profileImage setImage:messageAtRowIndex.author.profileImage];
            cell.profileImage.layer.cornerRadius =
                cell.profileImage.frame.size.height / 2;
            cell.profileImage.layer.masksToBounds = YES;
        }


        [cell.contentView setBackgroundColor:messageAtRowIndex.pingingUser
                              ? [UIColor colorWithRed:0.18f
                                                green:0.176f
                                                 blue:0.157f
                                                alpha:1.00f]
                              : [UIColor clearColor]];

        cell.contentView.layer.cornerRadius  = 0;
        cell.contentView.layer.masksToBounds = YES;

        for (UIView *subView in cell.subviews) {
            if ([subView isKindOfClass:[UIImageView class]]) {
                [subView removeFromSuperview];
            }
            if ([subView isKindOfClass:[DCChatVideoAttachment class]]) {
                [subView removeFromSuperview];
            }
            if ([subView isKindOfClass:[QLPreviewController class]]) {
                [subView removeFromSuperview];
            }
        }

        float contentWidth    = UIScreen.mainScreen.bounds.size.width - 63;
        CGSize authorNameSize = [messageAtRowIndex.author.globalName
                 sizeWithFont:[UIFont boldSystemFontOfSize:15]
            constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                lineBreakMode:(NSLineBreakMode
                              )UILineBreakModeWordWrap];

        // dispatch_async(dispatch_get_main_queue(), ^{
        CGFloat imageViewOffset = (!messageAtRowIndex.isGrouped
                                       ? authorNameSize.height
                                           + (messageAtRowIndex.referencedMessage != nil ? 16 : 0)
                                       : 0
                                  )
            + (
                                      [messageAtRowIndex.content length] != 0
                                          ? height
                                          : (!messageAtRowIndex.isGrouped ? 10 : 0) // ???
            );

        for (id attachment in messageAtRowIndex.attachments) {
            if ([attachment isKindOfClass:[UIImage class]]) {
                UIImageView *imageView = UIImageView.new;
                UIImage *image         = attachment;
                CGFloat aspectRatio    = image.size.width / image.size.height;
                int newWidth           = 200 * aspectRatio;
                int newHeight          = 200;
                if (newWidth > self.chatTableView.width - 66) {
                    newWidth  = self.chatTableView.width - 66;
                    newHeight = newWidth / aspectRatio;
                }
                [imageView setFrame:CGRectMake(
                                        55, imageViewOffset, newWidth, newHeight
                                    )];
                [imageView setImage:attachment];
                imageViewOffset += newHeight;

                [imageView setContentMode:UIViewContentModeScaleAspectFit];

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
            }
        }
        return cell;
    }
    NSCAssert(0, @"Should be unreachable");
    abort();
}


- (CGFloat)tableView:(UITableView *)tableView
    heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    DCMessage *messageAtRowIndex = [self.messages objectAtIndex:indexPath.row];

    int attachmentHeight = 0;
    for (id attachment in messageAtRowIndex.attachments) {
        if ([attachment isKindOfClass:[UIImage class]]) {
            UIImage *image      = attachment;
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
        }
    }
    return messageAtRowIndex.contentHeight
        + attachmentHeight
        + (attachmentHeight ? 11 : 0);
}


- (void)tableView:(UITableView *)tableView
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    self.selectedMessage = self.messages[indexPath.row];

    if ([self.selectedMessage.author.snowflake
            isEqualToString:DCServerCommunicator.sharedInstance.snowflake]) {
        UIActionSheet *messageActionSheet =
            [[UIActionSheet alloc] initWithTitle:self.selectedMessage.content
                                        delegate:self
                               cancelButtonTitle:@"Cancel"
                          destructiveButtonTitle:@"Delete"
                               otherButtonTitles:@"Copy Message ID", 
                                                 @"View Profile", 
                                                 nil];
        [messageActionSheet setTag:1];
        [messageActionSheet setDelegate:self];
        [messageActionSheet showFromToolbar:self.toolbar];
    } else {
        UIActionSheet *messageActionSheet = [[UIActionSheet alloc]
                     initWithTitle:self.selectedMessage.content
                          delegate:self
                 cancelButtonTitle:@"Cancel"
            destructiveButtonTitle:nil
                 otherButtonTitles:@"Reply", 
                                   @"Mention", 
                                   @"Copy Message ID", 
                                   @"View Profile", 
                                   nil];
        [messageActionSheet setTag:3];
        [messageActionSheet setDelegate:self];
        [messageActionSheet showFromToolbar:self.toolbar];
    }
}

- (void)actionSheet:(UIActionSheet *)popup
    clickedButtonAtIndex:(NSInteger)buttonIndex {
    if ([popup tag] == 1) {
        if (buttonIndex == 0) {
            [self.selectedMessage deleteMessage];
        } else if (buttonIndex == 1) {
            UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
            [pasteboard setString:self.selectedMessage.snowflake];
        } else if (buttonIndex == 2) {
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
        if (buttonIndex == 0) {
            // REPLY
            // NSLog(@"penis");
            self.inputField.text = [NSString
                stringWithFormat:@"> %@\n<@%@> ", self.selectedMessage.content,
                                 self.selectedMessage.author.snowflake];
        } else if (buttonIndex == 1) {
            self.inputField.text = [NSString
                stringWithFormat:@"%@<@%@> ", self.inputField.text,
                                 self.selectedMessage.author.snowflake];
        } else if (buttonIndex == 2) {
            UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
            [pasteboard setString:self.selectedMessage.snowflake];
        } else if (buttonIndex == 3) {
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

    int keyboardHeight =
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
        setHeight:self.view.height - keyboardHeight - self.toolbar.height];
    [self.toolbar setY:self.view.height - keyboardHeight - self.toolbar.height];
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
    float keyboardAnimationDuration = [[notification.userInfo
        objectForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue];
    int keyboardAnimationCurve      = [[notification.userInfo
        objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue];

    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:keyboardAnimationDuration];
    [UIView setAnimationCurve:keyboardAnimationCurve];
    [UIView setAnimationBeginsFromCurrentState:YES];
    [self.chatTableView setHeight:self.view.height - self.toolbar.height];
    [self.toolbar setY:self.view.height - self.toolbar.height];
    [UIView commitAnimations];
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
            [DCServerCommunicator.sharedInstance.selectedChannel
                sendMessage:self.inputField.text];
            [self.inputField setText:@""];
            self.inputFieldPlaceholder.hidden = NO;
            lastTimeInterval                  = 0;
        } else {
            [self.inputField resignFirstResponder];
        }

        if (self.viewingPresentTime) {
            [self.chatTableView
                setContentOffset:CGPointMake(
                                     0,
                                     self.chatTableView.contentSize.height
                                         - self.chatTableView.frame.size.height
                                 )
                        animated:YES];
        }
    });
}

- (void)tappedImage:(UITapGestureRecognizer *)sender {
    [self.inputField resignFirstResponder];
    self.selectedImage = ((UIImageView *)sender.view).image;
    [self performSegueWithIdentifier:@"Chat to Gallery" sender:self];
}

- (void)tappedVideo:(UITapGestureRecognizer *)sender {
    [self.inputField resignFirstResponder];
#ifdef DEBUG
    NSLog(@"Tapped video!");
#endif
    dispatch_async(dispatch_get_main_queue(), ^{
        MPMoviePlayerViewController *player;
        @try {
            NSURL *url = ((DCChatVideoAttachment *)sender.view.superview).videoURL;
            player = [[MPMoviePlayerViewController alloc] initWithContentURL:url];
        } @catch (id exception) {
#ifdef DEBUG
            NSLog(@"Silly movie error %@", exception);
#endif
        }
        [[NSNotificationCenter defaultCenter] addObserver:self
                                         selector:@selector(moviePlaybackDidFinish:)
                                             name:MPMoviePlayerPlaybackDidFinishNotification
                                           object:player.moviePlayer];
        player.moviePlayer.repeatMode = MPMovieRepeatModeOne;
        UIWindow *backgroundWindow =
            [[UIApplication sharedApplication] keyWindow];
        [player.view setFrame:backgroundWindow.frame];
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
    }
#ifdef DEBUG
    else if ([reason intValue] == MPMovieFinishReasonUserExited) {
        NSLog(@"User exited playback");
    } else if ([reason intValue] == MPMovieFinishReasonPlaybackEnded) {
        NSLog(@"Playback ended normally");
    }
#endif
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"Chat to Gallery"]) {
        DCImageViewController *imageViewController =
            [segue destinationViewController];

        if ([imageViewController isKindOfClass:DCImageViewController.class]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [imageViewController.imageView setImage:self.selectedImage];
            });
        }
    }
    if ([segue.identifier isEqualToString:@"Chat to Right Sidebar"]) {
        DCCInfoViewController *rightSidebar = [segue destinationViewController];

        if ([rightSidebar isKindOfClass:DCCInfoViewController.class]) {
            [rightSidebar.navigationItem setTitle:self.navigationItem.title];
        }
    }

    if ([segue.destinationViewController class] ==
        [DCContactViewController class]) {
        [((DCContactViewController *)segue.destinationViewController
        ) setSelectedUser:self.selectedMessage.author];
    } else if ([segue.destinationViewController class] ==
               [ODCContactViewController class]) {
        [((ODCContactViewController *)segue.destinationViewController
        ) setSelectedUser:self.selectedMessage.author];
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
    [picker dismissModalViewControllerAnimated:YES];
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
    [self dismissModalViewControllerAnimated:YES];
}

- (void)get50MoreMessages:(UIRefreshControl *)control {
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
