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
#import <MediaPlayer/MediaPlayer.h>

#import "DCCInfoViewController.h"
#import "DCChatTableCell.h"
#import "DCChatVideoAttachment.h"
#import "DCChatGifAttachment.h"
#import "DCGifInfo.h"
#import "DCImageViewController.h"
#import "DCMessage.h"
#import "DCServerCommunicator.h"
#import "DCTools.h"
#import "DCUser.h"
#import "QuickLook/QuickLook.h"
#import "TRMalleableFrameView.h"
#import "UILazyImage.h"
#import "UILazyImageView.h"
#import "DCCacheManager.h"
#import "DTLinkButton.h"
#import "DCMarkdownParser.h"
#import "DTCoreTextLayouter.h"
#import "DTCoreTextLayoutFrame.h"
#import "DTImageTextAttachment.h"

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

// dynamic message box vars
CGFloat _baseToolbarHeight;
CGFloat _baseInputHeight;
CGFloat _baseMsgFieldBGHeight;
CGFloat _baseInputOriginY;

@implementation DCChatViewController

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
    }
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations {
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

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

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"experimentalMode"]) {
        [self.navigationController.navigationBar
            setBackgroundImage:[UIImage imageNamed:@"TbarBG"]
                 forBarMetrics:UIBarMetricsDefault];
    }
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
           selector:@selector(emojiImageReady:)
               name:@"EMOJI IMAGE READY"
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
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleConnectionRestored)
                                               name:@"CONNECTION_RESTORED"
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
        [self.nbmodaldone setBackgroundImage:[UIImage imageNamed:@"BarButtonDone"]
                                    forState:UIControlStateNormal
                                  barMetrics:UIBarMetricsDefault];
        [self.nbmodaldone
            setBackgroundImage:[UIImage imageNamed:@"BarButtonDonePressed"]
                      forState:UIControlStateHighlighted
                    barMetrics:UIBarMetricsDefault];

        // [[UIToolbar appearance] setBackgroundImage:[UIImage imageNamed:@"ToolbarBG"]
        //                         forToolbarPosition:UIToolbarPositionAny
        //                                 barMetrics:UIBarMetricsDefault];

        UIImage *toolbarBG = [UIImage imageNamed:@"ToolbarBG"];
        UIEdgeInsets toolbarCaps = UIEdgeInsetsMake(23, 0, 20, 0); // top/bottom caps, full width stretches center
        UIImage *stretchableToolbarBG;
        if ([toolbarBG respondsToSelector:@selector(resizableImageWithCapInsets:resizingMode:)]) {
            stretchableToolbarBG = [toolbarBG resizableImageWithCapInsets:toolbarCaps
                                                             resizingMode:UIImageResizingModeStretch];
        } else {
            stretchableToolbarBG = [toolbarBG stretchableImageWithLeftCapWidth:0 topCapHeight:10];
        }
        self.toolbarBG.image = stretchableToolbarBG;
        self.toolbar.layer.shadowColor   = [UIColor blackColor].CGColor;
        self.toolbar.layer.shadowOffset  = CGSizeMake(0, -1);
        self.toolbar.layer.shadowOpacity = 0.3f;
        self.toolbar.layer.shadowRadius  = 1.5f;
        self.toolbar.clipsToBounds       = NO;

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


        [self.sendButton setBackgroundImage:[UIImage imageNamed:@"SendMessageButton"]
                                   forState:UIControlStateNormal];
        [self.sendButton setBackgroundImage:[UIImage imageNamed:@"SendMessageButtonPressed"]
                                   forState:UIControlStateHighlighted];

        [self.photoButton setBackgroundImage:[UIImage imageNamed:@"CameraButton"]
                                    forState:UIControlStateNormal];
        [self.photoButton setBackgroundImage:[UIImage imageNamed:@"CameraButtonPressed"]
                                    forState:UIControlStateHighlighted];
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
    // resizable inputField
    _baseInputHeight      = self.inputField.frame.size.height;
    _baseMsgFieldBGHeight = self.messageFieldBG.frame.size.height;
    _baseToolbarHeight    = self.toolbar.frame.size.height;
    _baseInputOriginY = self.inputField.frame.origin.y;

    self.inputField.scrollEnabled = NO;

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
    
    // Message Input bitmap
    UIImage *img = [UIImage imageNamed:@"MessageField"];
    UIEdgeInsets caps = UIEdgeInsetsMake(15, 15, 15, 15);
    
    UIImage *stretch;
    if ([img respondsToSelector:@selector(resizableImageWithCapInsets:resizingMode:)]) {
        stretch = [img resizableImageWithCapInsets:caps resizingMode:UIImageResizingModeStretch];
    } else {
        stretch = [img stretchableImageWithLeftCapWidth:15 topCapHeight:15];
    }
    
    self.messageFieldBG.image = stretch;

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
    [self resizeInputField];
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

            // old cache REMOVE LATER
            // [self.heightCache removeAllObjects];
            [[DCCacheManager sharedInstance] invalidateAllMessages];
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

- (void)handleConnectionRestored {
    assertMainThread();

    // Only backfill if we have messages loaded and are watching present time
    if (!self.messages || self.messages.count == 0 || !self.viewingPresentTime) {
        return;
    }

    DCChannel *channel    = DCServerCommunicator.sharedInstance.selectedChannel;
    DCMessage *lastMessage = [self.messages lastObject];
    if (!channel || !lastMessage) {
        return;
    }

    NSString *lastSnowflake = lastMessage.snowflake;

    dispatch_async([self get_chat_messages_queue], ^{
        NSArray *newMessages = [channel getMessages:50 afterMessage:lastMessage];
        if (!newMessages || newMessages.count == 0) {
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            // Dedup — gateway replay may have already inserted some of these
            // via MESSAGE_CREATE before the REST backfill completed
            NSMutableArray *toInsert = NSMutableArray.new;
            for (DCMessage *msg in newMessages) {
                BOOL alreadyPresent = NO;
                for (DCMessage *existing in self.messages) {
                    if ([existing.snowflake isEqualToString:msg.snowflake]) {
                        alreadyPresent = YES;
                        break;
                    }
                }
                if (!alreadyPresent) {
                    [toInsert addObject:msg];
                }
            }

            if (toInsert.count == 0) {
                return;
            }

            // Verify we're still in the same channel before touching the table
            if (DCServerCommunicator.sharedInstance.selectedChannel != channel) {
                return;
            }

            NSMutableArray *indexPaths = NSMutableArray.new;
            for (DCMessage *msg in toInsert) {
                NSIndexPath *path = [NSIndexPath indexPathForRow:self.messages.count inSection:0];
                [self.messages addObject:msg];
                [indexPaths addObject:path];
            }

            [self.chatTableView beginUpdates];
            [self.chatTableView insertRowsAtIndexPaths:indexPaths
                                     withRowAnimation:UITableViewRowAnimationNone];
            [self.chatTableView endUpdates];

            // Scroll to bottom since we were at present time
            [self scrollWithIndex:[indexPaths lastObject]];

            NSLog(@"[CONNECTION_RESTORED] Backfilled %lu messages after %@",
                  (unsigned long)toInsert.count, lastSnowflake);
        });
    });
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
    for (NSIndexPath *indexPath in indexPaths) {
        DCMessage *msg = self.messages[indexPath.row];
        // old cache REMOVE LATER
        // [self.heightCache removeObjectForKey:msg.snowflake];
        [[DCCacheManager sharedInstance] invalidateSnowflake:msg.snowflake];
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
    // Old cache, REMOVE LATER
    // [self.heightCache removeObjectForKey:message.snowflake];
    [[DCCacheManager sharedInstance] invalidateSnowflake:message.snowflake];
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

                // if (newMessage.isGrouped) {
                //     float contentWidth =
                //         UIScreen.mainScreen.bounds.size.width - 63;
                //     CGSize authorNameSize = [[newMessage.author displayNameInGuild:DCServerCommunicator.sharedInstance.selectedChannel.parentGuild]
                //              sizeWithFont:[UIFont boldSystemFontOfSize:15]
                //         constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                //             lineBreakMode:(NSLineBreakMode)UILineBreakModeWordWrap];

                //     newMessage.contentHeight -= authorNameSize.height + 4;
                // }
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
        DCMessage *prevMessage = (curIdx != NSNotFound && curIdx > 0) ? [self.messages objectAtIndex:curIdx - 1] : nil;
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

                // if (newMessage.isGrouped) {
                //     float contentWidth =
                //         UIScreen.mainScreen.bounds.size.width - 63;
                //     CGSize authorNameSize = [[newMessage.author displayNameInGuild:DCServerCommunicator.sharedInstance.selectedChannel.parentGuild]
                //              sizeWithFont:[UIFont boldSystemFontOfSize:15]
                //         constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                //             lineBreakMode:(NSLineBreakMode)UILineBreakModeWordWrap];

                //     newMessage.contentHeight -= authorNameSize.height + 4;
                // }
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
            CGSize authorNameSize = [[newMessage.author displayNameInGuild:DCServerCommunicator.sharedInstance.selectedChannel.parentGuild]
                     sizeWithFont:[UIFont boldSystemFontOfSize:15]
                constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                    lineBreakMode:(NSLineBreakMode)UILineBreakModeWordWrap];

            newMessage.contentHeight -= authorNameSize.height + 4;
        }
    } else if (newMessage.isGrouped) {
        newMessage.isGrouped = false;
        float contentWidth =
            UIScreen.mainScreen.bounds.size.width - 63;
        CGSize authorNameSize = [[newMessage.author displayNameInGuild:DCServerCommunicator.sharedInstance.selectedChannel.parentGuild]
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
        DCUser *user = [DCServerCommunicator.sharedInstance userForSnowflake:userId];
        if (user) {
            [typingNames addObject:[user displayName]];
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

        int scrollOffset = -self.chatTableView.height;
        for (DCMessage *newMessage in newMessages) {
            @autoreleasepool {
                if (!newMessage.author.profileImage) {
                    [DCTools getUserAvatar:newMessage.author];
                }

                if (newMessage.referencedMessage && 
                    newMessage.referencedMessage.author &&
                    !newMessage.referencedMessage.author.profileImage) {
                    [DCTools getUserAvatar:newMessage.referencedMessage.author];
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
            NSRange range        = NSMakeRange(0, [newMessages count]);
            NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:range];

            NSInteger rowCount = [self.chatTableView numberOfRowsInSection:0];
            if (rowCount != self.messages.count) {
                NSLog(@"%s: Row count mismatch! Expected %ld but got %ld", __PRETTY_FUNCTION__, (long)self.messages.count, (long)rowCount);
                [self.messages insertObjects:newMessages atIndexes:indexSet];
                [self handleAsyncReload];
            } else {
                NSMutableArray *indexPaths = [[NSMutableArray alloc] init];
                [indexSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
                    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:idx inSection:0];
                    [indexPaths addObject:indexPath];
                }];
                [self.chatTableView beginUpdates];
                [self.messages insertObjects:newMessages atIndexes:indexSet];
                [self.chatTableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
                [self.chatTableView endUpdates];
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
        // Precalculate heights for both orientations on iPad
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
            CGFloat screenWidth  = UIScreen.mainScreen.bounds.size.width;
            CGFloat screenHeight = UIScreen.mainScreen.bounds.size.height;
            CGFloat portraitWidth  = MIN(screenWidth, screenHeight);
            CGFloat landscapeWidth = MAX(screenWidth, screenHeight);
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                for (DCMessage *message in newMessages) {
                    if (!message.snowflake) continue;
                    // Check for unloaded attachments
                    BOOL hasUnloaded = NO;
                    for (id attachment in message.attachments) {
                        if ([attachment isKindOfClass:[NSArray class]] ||
                            ([attachment isKindOfClass:[DCGifInfo class]] && !((DCGifInfo *)attachment).staticThumbnail)) {
                            hasUnloaded = YES;
                            break;
                        }
                    }
                    if (hasUnloaded) continue;
                    
                    // Precalculate portrait
                    if (![[DCCacheManager sharedInstance] cacheEntryForSnowflake:message.snowflake width:portraitWidth]) {
                        CGFloat h = [self calculateHeightForMessage:message 
                                                         tableWidth:portraitWidth 
                                                   followedByGrouped:NO];
                        DCMessageCacheEntry *entry = [DCMessageCacheEntry new];
                        entry.cellHeight = h;
                        [[DCCacheManager sharedInstance] setCacheEntry:entry forSnowflake:message.snowflake width:portraitWidth];
                    }
                    // Precalculate landscape
                    if (![[DCCacheManager sharedInstance] cacheEntryForSnowflake:message.snowflake width:landscapeWidth]) {
                        CGFloat h = [self calculateHeightForMessage:message 
                                                         tableWidth:landscapeWidth 
                                                   followedByGrouped:NO];
                        DCMessageCacheEntry *entry = [DCMessageCacheEntry new];
                        entry.cellHeight = h;
                        [[DCCacheManager sharedInstance] setCacheEntry:entry forSnowflake:message.snowflake width:landscapeWidth];
                    }
                }
            });
        }
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
            // NSSet *specialMessageTypes =
            //     [NSSet setWithArray:@[ @1, @2, @3, @4, @5, @6, @7, @8, @18 ]];

            // if (messageAtRowIndex.isGrouped
            //     && ![specialMessageTypes
            //         containsObject:@(messageAtRowIndex.messageType)]) {
            //     cell = [tableView dequeueReusableCellWithIdentifier:
            //                           @"OldMode Grouped Message Cell"];
            // } else if (messageAtRowIndex.referencedMessage != nil) {
            //     cell = [tableView dequeueReusableCellWithIdentifier:
            //                           @"OldMode Reply Message Cell"];
            // } else if ([specialMessageTypes
            //                containsObject:@(messageAtRowIndex.messageType)]) {
            //     cell = [tableView dequeueReusableCellWithIdentifier:
            //                           @"OldMode Universal Typehandler Cell"];
            // } else {
            //     cell = [tableView
            //         dequeueReusableCellWithIdentifier:@"OldMode Message Cell"];
            // }

            // if (messageAtRowIndex.referencedMessage != nil) {
            //     cell.referencedAuthorLabel.text = [messageAtRowIndex.referencedMessage.author 
            //         displayNameInGuild:DCServerCommunicator.sharedInstance.selectedChannel.parentGuild];
            //     cell.referencedMessage.text     = messageAtRowIndex.referencedMessage.content;
            //     cell.referencedMessage.frame    = CGRectMake(
            //         messageAtRowIndex.referencedMessage.authorNameWidth,
            //         cell.referencedMessage.y,
            //         self.chatTableView.width - messageAtRowIndex.authorNameWidth,
            //         cell.referencedMessage.height
            //     );

            //     if (messageAtRowIndex.referencedMessage.author.profileImage) {
            //         cell.referencedProfileImage.image =
            //             messageAtRowIndex.referencedMessage.author.profileImage;
            //     } else {
            //         [DCTools getUserAvatar:messageAtRowIndex.referencedMessage.author];
            //     }
            // }

            // if (!messageAtRowIndex.isGrouped) {
            //     cell.authorLabel.text = [messageAtRowIndex.author 
            //         displayNameInGuild:DCServerCommunicator.sharedInstance.selectedChannel.parentGuild];
            // }

            // cell.contentTextView.text = messageAtRowIndex.content;

            // cell.contentTextView.height = [cell.contentTextView
            //                                   sizeThatFits:CGSizeMake(
            //                                                    cell.contentTextView.width, MAXFLOAT
            //                                                )]
            //                                   .height;

            // if (!messageAtRowIndex.isGrouped) {
            //     cell.profileImage.image = messageAtRowIndex.author.profileImage;
            // }

            // cell.contentView.backgroundColor = messageAtRowIndex.pingingUser
            //     ? [UIColor redColor]
            //     : [UIColor clearColor];

            // // NSLog(@"%@", cell.subviews);
            // cell.contentTextView.hidden = NO;
            // for (UIView *subView in cell.subviews) {
            //     @autoreleasepool {
            //         if ([subView isKindOfClass:[UILazyImageView class]]
            //          || [subView isKindOfClass:[DCChatVideoAttachment class]]
            //          || [subView isKindOfClass:[QLPreviewController class]]
            //          || [subView isKindOfClass:[UIActivityIndicatorView class]]
            //             ) {
            //             [subView removeFromSuperview];
            //         }
            //     }
            // }
            // // dispatch_async(dispatch_get_main_queue(), ^{
            // float contentWidth = self.chatTableView.width - 63;
            // CGSize textSize = [messageAtRowIndex.content
            //          sizeWithFont:[UIFont systemFontOfSize:14]
            //     constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
            //         lineBreakMode:NSLineBreakByWordWrapping];
            // CGFloat correctTextHeight = ceil(textSize.height) + 2;
            // int imageViewOffset = correctTextHeight + 37;

            // // NSLog(@"[Message] snowflake: %@ attachmentCount: %d attachments: %lu", 
            // //     messageAtRowIndex.snowflake, 
            // //     messageAtRowIndex.attachmentCount,
            // //     (unsigned long)messageAtRowIndex.attachments.count);
            // for (id attachment in messageAtRowIndex.attachments) {
            //     NSLog(@"[Attachment] class: %@", NSStringFromClass([attachment class]));
            //     @autoreleasepool {
            //         if ([attachment isKindOfClass:[UILazyImage class]]) {
            //             UILazyImage *lazyImage     = attachment;
            //             UILazyImageView *imageView = [UILazyImageView new];
            //             imageView.frame            = CGRectMake(
            //                 11, imageViewOffset,
            //                 self.chatTableView.width - 22, 200
            //             );
            //             imageView.image       = lazyImage.image;
            //             imageView.contentMode = UIViewContentModeScaleAspectFit;
            //             imageView.imageURL    = lazyImage.imageURL;

            //             imageViewOffset += imageView.height + 11;

            //             UITapGestureRecognizer *singleTap =
            //                 [[UITapGestureRecognizer alloc]
            //                     initWithTarget:self
            //                             action:@selector(tappedImage:)];
            //             singleTap.numberOfTapsRequired   = 1;
            //             imageView.userInteractionEnabled = YES;
            //             [imageView addGestureRecognizer:singleTap];

            //             [cell addSubview:imageView];
            //         } else if ([attachment
            //                        isKindOfClass:[DCChatVideoAttachment class]]) {
            //             ////NSLog(@"add video!");
            //             DCChatVideoAttachment *video = attachment;

            //             UITapGestureRecognizer *singleTap =
            //                 [[UITapGestureRecognizer alloc]
            //                     initWithTarget:self
            //                             action:@selector(tappedVideo:)];
            //             singleTap.numberOfTapsRequired = 1;
            //             [video.playButton addGestureRecognizer:singleTap];
            //             video.playButton.userInteractionEnabled = YES;

            //             CGFloat aspectRatio = video.thumbnail.image.size.width /
            //                 video.thumbnail.image.size.height;
            //             int newWidth  = 200 * aspectRatio;
            //             int newHeight = 200;
            //             if (newWidth > self.chatTableView.width - 66) {
            //                 newWidth  = self.chatTableView.width - 66;
            //                 newHeight = newWidth / aspectRatio;
            //             }
            //             video.frame = CGRectMake(55, imageViewOffset, newWidth, newHeight);
            //             [video prepareForDisplay];

            //             imageViewOffset += newHeight;

            //             [cell addSubview:video];
            //         } else if ([attachment isKindOfClass:[DCGifInfo class]]) {
            //             DCGifInfo *gifInfo = attachment;
            //             DCChatGifAttachment *gif = [[[NSBundle mainBundle]
            //                 loadNibNamed:@"DCChatGifAttachment"
            //                        owner:nil
            //                      options:nil] objectAtIndex:0];
            //             gif.staticThumbnail    = gifInfo.staticThumbnail;
            //             gif.gifThumbnail.image = gifInfo.staticThumbnail;
            //             gif.gifURL             = gifInfo.gifURL;
            //             CGFloat aspectRatio = gif.staticThumbnail.size.width / gif.staticThumbnail.size.height;
            //             int newWidth  = 200 * aspectRatio;
            //             int newHeight = 200;
            //             if (newWidth > self.chatTableView.width - 66) {
            //                 newWidth  = self.chatTableView.width - 66;
            //                 newHeight = newWidth / aspectRatio;
            //             }
            //             [gif setFrame:CGRectMake(55, imageViewOffset, newWidth, newHeight)];
            //             [gif prepareForDisplay];
            //             imageViewOffset += newHeight;
            //             [cell addSubview:gif];
            //         } else if ([attachment isKindOfClass:[QLPreviewController class]]) {
            //             ////NSLog(@"Add QuickLook!");
            //             QLPreviewController *preview = attachment;

            //             /*UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer
            //              alloc] initWithTarget:self action:@selector(tappedVideo:)];
            //              singleTap.numberOfTapsRequired = 1;
            //              [video.playButton addGestureRecognizer:singleTap];
            //              video.playButton.userInteractionEnabled = YES;

            //              CGFloat aspectRatio = video.thumbnail.image.size.width /
            //              video.thumbnail.image.size.height; int newWidth = 200 *
            //              aspectRatio; int newHeight = 200; if (newWidth >
            //              self.chatTableView.width - 66) { newWidth =
            //              self.chatTableView.width - 66; newHeight = newWidth /
            //              aspectRatio;
            //              }
            //              [video setFrame:CGRectMake(55, imageViewOffset, newWidth,
            //              newHeight)];*/

            //             imageViewOffset += 210;

            //             [cell addSubview:preview.view];
            //         } else if ([attachment isKindOfClass:[NSArray class]]) {
            //             NSArray *dimensions = attachment;
            //             if (dimensions.count == 2) {
            //                 int width  = [dimensions[0] intValue];
            //                 int height = [dimensions[1] intValue];
            //                 if (width <= 0 || height <= 0) {
            //                     continue;
            //                 }
            //                 CGFloat aspectRatio = (CGFloat)width / height;
            //                 int newWidth        = 200 * aspectRatio;
            //                 int newHeight       = 200;
            //                 if (newWidth > self.chatTableView.width - 66) {
            //                     newWidth  = self.chatTableView.width - 66;
            //                     newHeight = newWidth / aspectRatio;
            //                 }
            //                 UIActivityIndicatorView *activityIndicator =
            //                     [[UIActivityIndicatorView alloc]
            //                         initWithActivityIndicatorStyle:
            //                             UIActivityIndicatorViewStyleWhite];
            //                 [activityIndicator setFrame:CGRectMake(
            //                                                 11, imageViewOffset, newWidth,
            //                                                 newHeight
            //                                             )];
            //                 [activityIndicator setContentMode:UIViewContentModeScaleAspectFit];
            //                 imageViewOffset += newHeight + 11;

            //                 [cell addSubview:activityIndicator];
            //                 [activityIndicator startAnimating];
            //             }
            //         }
            //     }
            // }
        } else {
            CFAbsoluteTime cellStart = CFAbsoluteTimeGetCurrent();
            static NSSet *specialMessageTypes = nil;
            static UIColor *replyHighlightColor = nil;
            static UIColor *pingColor = nil;
            static UIColor *normalColor = nil;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                specialMessageTypes = [NSSet setWithArray:@[ @1, @2, @3, @4, @5, @6, @7, @8, @18 ]];
                replyHighlightColor = [UIColor colorWithRed:55/255.0f green:59/255.0f blue:64/255.0f alpha:1.0f];
                pingColor           = [UIColor colorWithRed:46/255.0f green:45/255.0f blue:40/255.0f alpha:1.0f];
                normalColor         = [UIColor colorWithRed:40/255.0f green:41/255.0f blue:46/255.0f alpha:1.0f];
            });

            // TICK(init);
            if (messageAtRowIndex.isGrouped
                && ![specialMessageTypes
                    containsObject:@(messageAtRowIndex.messageType)]) {
                cell = [tableView
                    dequeueReusableCellWithIdentifier:@"Grouped Message Cell"];
                if ([cell.configuredSnowflake isEqualToString:messageAtRowIndex.snowflake]
                    && cell.configuredWidth == self.chatTableView.bounds.size.width
                    && !(self.replyingToMessage && [self.replyingToMessage.snowflake isEqualToString:messageAtRowIndex.snowflake])
                    && !(self.editingMessage && [self.editingMessage.snowflake isEqualToString:messageAtRowIndex.snowflake])) {
                    return cell;
                }
            } else if (messageAtRowIndex.referencedMessage != nil) {
                cell = [tableView
                    dequeueReusableCellWithIdentifier:@"Reply Message Cell"];
                if ([cell.configuredSnowflake isEqualToString:messageAtRowIndex.snowflake]
                    && cell.configuredWidth == self.chatTableView.bounds.size.width
                    && !(self.replyingToMessage && [self.replyingToMessage.snowflake isEqualToString:messageAtRowIndex.snowflake])
                    && !(self.editingMessage && [self.editingMessage.snowflake isEqualToString:messageAtRowIndex.snowflake])) {
                    return cell;
                }
            } else if ([specialMessageTypes
                           containsObject:@(messageAtRowIndex.messageType)]) {
                cell = [tableView dequeueReusableCellWithIdentifier:
                                      @"Universal Typehandler Cell"];
                if ([cell.configuredSnowflake isEqualToString:messageAtRowIndex.snowflake]
                    && cell.configuredWidth == self.chatTableView.bounds.size.width
                    && !(self.replyingToMessage && [self.replyingToMessage.snowflake isEqualToString:messageAtRowIndex.snowflake])
                    && !(self.editingMessage && [self.editingMessage.snowflake isEqualToString:messageAtRowIndex.snowflake])) {
                    return cell;
                }
            } else {
                cell = [tableView dequeueReusableCellWithIdentifier:@"Message Cell"];

                if ([cell.configuredSnowflake isEqualToString:messageAtRowIndex.snowflake]
                    && cell.configuredWidth == self.chatTableView.bounds.size.width
                    && !(self.replyingToMessage && [self.replyingToMessage.snowflake isEqualToString:messageAtRowIndex.snowflake])
                    && !(self.editingMessage && [self.editingMessage.snowflake isEqualToString:messageAtRowIndex.snowflake])) {
                    return cell;
                }
            }
            // TOCK(init);
            cell.configuredSnowflake = nil;
            // cleanup loop
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
                    if ([subView isKindOfClass:[UIButton class]] && 
                        ![subView isKindOfClass:[DTLinkButton class]]) {
                        [subView removeFromSuperview];
                    }
                    if ([subView isKindOfClass:[DCChatGifAttachment class]]) {
                        [(DCChatGifAttachment *)subView stopPlayback];
                        [subView removeFromSuperview];
                    }
                    if ([subView isKindOfClass:[UIActivityIndicatorView class]]) {
                        [subView removeFromSuperview];
                    }
                }
            }

            [cell.contentTextView removeAllCustomViewsForLinks];
            [cell.referencedMessage removeAllCustomViewsForLinks];

            if (messageAtRowIndex.referencedMessage != nil) {
                cell.referencedAuthorLabel.text = [messageAtRowIndex.referencedMessage.author 
                    displayNameInGuild:DCServerCommunicator.sharedInstance.selectedChannel.parentGuild];
                
                NSAttributedString *referencedContent = [[DCMarkdownParser sharedParser]
                    attributedStringFromMarkdown:messageAtRowIndex.referencedMessage.content
                                     maxFontSize:10.0f
                                           color:[UIColor colorWithRed:128/255.0f
                                                                green:128/255.0f
                                                                 blue:128/255.0f
                                                                alpha:1.0f]];
                cell.referencedMessage.attributedString = referencedContent;
                
                cell.referencedMessage.frame = CGRectMake(
                    messageAtRowIndex.referencedMessage.authorNameWidth,
                    cell.referencedMessage.y,
                    self.chatTableView.width - messageAtRowIndex.authorNameWidth,
                    cell.referencedMessage.height
                );
                cell.referencedProfileImage.image = messageAtRowIndex.referencedMessage.author.profileImage;
                UIButton *referencedMessageButton = [UIButton buttonWithType:UIButtonTypeCustom];
                referencedMessageButton.frame = CGRectMake(
                    cell.referencedProfileImage.x, 
                    cell.referencedMessage.y, 
                    cell.referencedMessage.x + cell.referencedMessage.width - cell.referencedProfileImage.x, 
                    cell.referencedMessage.height
                );
                referencedMessageButton.exclusiveTouch = YES;
                [referencedMessageButton addTarget:self
                                             action:@selector(tappedReferencedMessage:)
                                      forControlEvents:UIControlEventTouchUpInside];
                [cell addSubview:referencedMessageButton];
            }

            if (!messageAtRowIndex.isGrouped) {
                NSString *displayName = [messageAtRowIndex.author 
                    displayNameInGuild:DCServerCommunicator.sharedInstance.selectedChannel.parentGuild];
                
                // Calculate natural sizes
                CGSize timestampSize = [messageAtRowIndex.prettyTimestamp 
                    sizeWithFont:cell.timestampLabel.font];
                CGSize nameSize = [displayName sizeWithFont:cell.authorLabel.font];
                
                CGFloat authorOriginX = cell.authorLabel.x;
                CGFloat gap = 8.0; // gap between name and timestamp
                CGFloat rightPadding = 8.0;
                CGFloat maxRightEdge = self.chatTableView.width - rightPadding;
                
                // Natural timestamp position — right after the name
                CGFloat naturalTimestampX = authorOriginX + nameSize.width + gap;
                
                // Maximum allowed timestamp X so it doesn't go off screen
                CGFloat maxTimestampX = maxRightEdge - timestampSize.width;
                
                // Timestamp sits at natural position unless that would push it too far
                CGFloat actualTimestampX = MIN(naturalTimestampX, maxTimestampX);
                
                // Author label is capped to whatever space is left before the timestamp
                CGFloat actualNameWidth = actualTimestampX - authorOriginX - gap;
                
                cell.authorLabel.text = displayName;
                cell.authorLabel.frame = CGRectMake(authorOriginX,
                                                    cell.authorLabel.y,
                                                    actualNameWidth,
                                                    cell.authorLabel.height);
                
                cell.timestampLabel.text = messageAtRowIndex.prettyTimestamp;
                cell.timestampLabel.frame = CGRectMake(actualTimestampX,
                                                       cell.timestampLabel.y,
                                                       timestampSize.width,
                                                       cell.timestampLabel.height);
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
            // Set colors
            // NSMutableAttributedString *colored = [messageAtRowIndex.attributedContent mutableCopy];
            // [colored enumerateAttribute:NSForegroundColorAttributeName
            //                     inRange:NSMakeRange(0, colored.length)
            //                     options:0
            //                  usingBlock:^(id value, NSRange range, BOOL *stop) {
            //     if (!value) {
            //         [colored addAttribute:NSForegroundColorAttributeName
            //                         value:[UIColor whiteColor]
            //                         range:range];
            //     }
            // }];
            // NSLog(@"attributedContent: %@", messageAtRowIndex.attributedContent);
            // cell.contentTextView.attributedString = colored;

            float contentWidth = self.chatTableView.width - 63;

            // Set content

            cell.contentTextView.attributedString = nil;
            [cell.contentTextView relayoutText];
            cell.contentTextView.attributedString = messageAtRowIndex.attributedContent;
            cell.contentTextView.delegate = self;
            cell.contentTextView.userInteractionEnabled = YES;

            NSCharacterSet *invisibleChars = [NSCharacterSet characterSetWithCharactersInString:@"\u00A0\u200B\n\r\t "];
            BOOL hasVisibleContent = [[messageAtRowIndex.content stringByTrimmingCharactersInSet:invisibleChars] length] > 0 
                || messageAtRowIndex.emojis.count > 0;

            CGFloat currentTextHeight = 0;
            if (hasVisibleContent && messageAtRowIndex.attributedContent) {
                DTCoreTextLayouter *layouter = [[DTCoreTextLayouter alloc] 
                    initWithAttributedString:messageAtRowIndex.attributedContent];
                CGRect proposedFrame = CGRectMake(0, 0, contentWidth, CGFLOAT_HEIGHT_UNKNOWN);
                DTCoreTextLayoutFrame *layoutFrame = [layouter layoutFrameWithRect:proposedFrame 
                                                                             range:NSMakeRange(0, 0)];
                currentTextHeight = ceil(CGRectGetHeight(layoutFrame.frame)) + 2;
            }

            if (!hasVisibleContent) {
                cell.contentTextView.attributedString = nil;
                cell.contentTextView.hidden = YES;
                cell.contentTextView.frame = CGRectMake(
                    cell.contentTextView.x,
                    cell.contentTextView.y,
                    cell.contentTextView.width,
                    0
                );
            } else {
                cell.contentTextView.hidden = NO;
                cell.contentTextView.frame = CGRectMake(
                    cell.contentTextView.x,
                    cell.contentTextView.y,
                    contentWidth,
                    currentTextHeight
                );
                [cell.contentTextView relayoutText];
            }

            // TOCK(content);

            cell.profileImage.image = messageAtRowIndex.author.profileImage;
            cell.profileImage.userInteractionEnabled = YES;

            UITapGestureRecognizer *profileTap = [[UITapGestureRecognizer alloc]
                initWithTarget:self
                        action:@selector(profileImageTapped:)];
            profileTap.numberOfTapsRequired = 1;
            [cell.profileImage addGestureRecognizer:profileTap];

            if ((self.replyingToMessage
                     && [self.replyingToMessage.snowflake
                         isEqualToString:messageAtRowIndex.snowflake])
                || (self.editingMessage
                    && [self.editingMessage.snowflake
                        isEqualToString:messageAtRowIndex.snowflake])) {
                cell.contentView.backgroundColor = replyHighlightColor;
            } else if (messageAtRowIndex.pingingUser) {
                cell.contentView.backgroundColor = pingColor;
            } else {
                cell.contentView.backgroundColor = normalColor;
            }


            BOOL cond = (messageAtRowIndex.messageType == 6
                || (messageAtRowIndex.messageType != 18
                    && (messageAtRowIndex.messageType < 1 || messageAtRowIndex.messageType > 8)));
            CGSize authorNameSize = CGSizeZero;
            if (!messageAtRowIndex.isGrouped && cond) {
                NSString *authorName = [messageAtRowIndex.author displayNameInGuild:
                    DCServerCommunicator.sharedInstance.selectedChannel.parentGuild];
                authorNameSize = CGSizeMake(
                    [authorName sizeWithFont:[UIFont boldSystemFontOfSize:15]].width,
                    [UIFont boldSystemFontOfSize:15].lineHeight
                );
            }
            CGSize contentSize = [messageAtRowIndex.content
                     sizeWithFont:[UIFont systemFontOfSize:14]
                constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT)
                    lineBreakMode:NSLineBreakByWordWrapping];
            contentSize.height = ceil(contentSize.height);
            CGFloat imageViewOffset;
            if (messageAtRowIndex.isGrouped) {
                imageViewOffset = MAX(currentTextHeight - 2, 18) + 4;
            } else {
                imageViewOffset = MAX(
                    (cond ? authorNameSize.height : 0)
                        + (messageAtRowIndex.attachmentCount ? (hasVisibleContent ? currentTextHeight - 2 : 0) : MAX(currentTextHeight - 2, 18))
                        + 10
                        + (messageAtRowIndex.referencedMessage != nil ? 16 : 0),
                    (cond ? authorNameSize.height : 0) + (hasVisibleContent ? [UIFont systemFontOfSize:14].lineHeight : 0) + 10
                );
            }

            for (id attachment in messageAtRowIndex.attachments) {
                @autoreleasepool {
                    if ([attachment isKindOfClass:[UILazyImage class]]) {
                        UILazyImageView *imageView = [UILazyImageView new];
                        UILazyImage *lazyImage     = attachment;
                        CGFloat aspectRatio        = lazyImage.image.size.width / lazyImage.image.size.height;
                        int newWidth  = messageAtRowIndex.isSticker ? 160 : (int)(200 * aspectRatio);
                        int newHeight = messageAtRowIndex.isSticker ? 160 : 200;
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

                        CGFloat aspectRatio = (video.thumbnail.image && video.thumbnail.image.size.height > 0)
                            ? video.thumbnail.image.size.width / video.thumbnail.image.size.height
                            : 16.0f / 9.0f; // default widescreen aspect ratio
                        int newWidth  = 200 * aspectRatio;
                        int newHeight = 200;
                        if (newWidth > self.chatTableView.width - 66) {
                            newWidth  = self.chatTableView.width - 66;
                            newHeight = newWidth / aspectRatio;
                        }
                        [video setFrame:CGRectMake(55, imageViewOffset, newWidth, newHeight)];
                        [video prepareForDisplay];

                        imageViewOffset += newHeight;

                        [cell addSubview:video];
                    } else if ([attachment isKindOfClass:[DCGifInfo class]]) {
                        DCGifInfo *gifInfo = attachment;
                        DCChatGifAttachment *gif = [[[NSBundle mainBundle]
                            loadNibNamed:@"DCChatGifAttachment"
                                   owner:nil
                                 options:nil] objectAtIndex:0];
                        gif.staticThumbnail    = gifInfo.staticThumbnail;
                        gif.gifThumbnail.image = gifInfo.staticThumbnail;
                        gif.gifURL             = gifInfo.gifURL;
                        CGFloat aspectRatio = gifInfo.staticThumbnail.size.width / gifInfo.staticThumbnail.size.height;
                        int newWidth  = (int)(200 * aspectRatio);
                        int newHeight = 200;
                        if (newWidth > self.chatTableView.width - 66) {
                            newWidth  = self.chatTableView.width - 66;
                            newHeight = newWidth / aspectRatio;
                        }
                        [gif setFrame:CGRectMake(55, imageViewOffset, newWidth, newHeight)];
                        imageViewOffset += newHeight;
                        [cell addSubview:gif];
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
        cell.configuredSnowflake = messageAtRowIndex.snowflake;
        cell.configuredWidth = self.chatTableView.bounds.size.width;
        CFAbsoluteTime cellEnd = CFAbsoluteTimeGetCurrent();
            // NSLog(@"[Cell] configuration took %.2fms", (cellEnd - cellStart) * 1000);
        }
    }
    return cell;
}

- (CGFloat)calculateHeightForMessage:(DCMessage *)message 
                          tableWidth:(CGFloat)tableWidth 
                    followedByGrouped:(BOOL)followedByGrouped {
    float contentWidth = tableWidth - 63;
    
    BOOL cond = (message.messageType == 6
        || (message.messageType != 18
            && (message.messageType < 1 || message.messageType > 8)));

    CGSize authorNameSize = CGSizeZero;
    if (!message.isGrouped && cond) {
        NSString *authorName = [message.author displayNameInGuild:
            DCServerCommunicator.sharedInstance.selectedChannel.parentGuild];
        // Single line measurement — don't allow wrapping
        CGSize measured = [authorName sizeWithFont:[UIFont boldSystemFontOfSize:15]];
        CGFloat singleLineHeight = [UIFont boldSystemFontOfSize:15].lineHeight;
        authorNameSize = CGSizeMake(measured.width, singleLineHeight);
    }

    CGFloat textHeight = message.textHeight > 2 ? message.textHeight - 2 : 0;
    CGSize contentSize = CGSizeMake(contentWidth, textHeight);

    NSCharacterSet *invisibleChars = [NSCharacterSet characterSetWithCharactersInString:@"\u00A0\u200B\n\r\t "];
    BOOL hasVisibleContent = [[message.content stringByTrimmingCharactersInSet:invisibleChars] length] > 0
        || message.emojis.count > 0;

    CGFloat contentHeight;
    if (message.isGrouped) {
        contentHeight = MAX(contentSize.height, 18) + 4;
    } else {
        // This changes the height of message cells, grouped : ungrouped
        CGFloat padding = followedByGrouped ? 10 : 14;
        contentHeight = MAX(
            (cond ? authorNameSize.height : 0)
                + (message.attachmentCount ? (hasVisibleContent ? contentSize.height : 0) : MAX(contentSize.height, 18))
                + padding
                + (message.referencedMessage != nil ? 16 : 0),
            (cond ? authorNameSize.height : 0) + (hasVisibleContent ? [UIFont systemFontOfSize:14].lineHeight : 0) + padding
        );
    }

    int attachmentHeight = 0;
    for (id attachment in message.attachments) {
        if ([attachment isKindOfClass:[UILazyImage class]]) {
            UIImage *image = ((UILazyImage *)attachment).image;
            CGFloat aspectRatio = image.size.width / image.size.height;
            int newWidth  = message.isSticker ? 160 : (int)(200 * aspectRatio);
            int newHeight = message.isSticker ? 160 : 200;
            if (newWidth > tableWidth - 66) {
                newWidth  = tableWidth - 66;
                newHeight = newWidth / aspectRatio;
            }
            attachmentHeight += newHeight;
        } else if ([attachment isKindOfClass:[DCChatVideoAttachment class]]) {
            DCChatVideoAttachment *video = attachment;
            CGFloat aspectRatio = (video.thumbnail.image && video.thumbnail.image.size.height > 0)
                ? video.thumbnail.image.size.width / video.thumbnail.image.size.height
                : 16.0f / 9.0f;
            int newWidth  = 200 * aspectRatio;
            int newHeight = 200;
            if (newWidth > tableWidth - 66) {
                newWidth  = tableWidth - 66;
                newHeight = newWidth / aspectRatio;
            }
            attachmentHeight += newHeight;
        } else if ([attachment isKindOfClass:[DCGifInfo class]]) {
            DCGifInfo *gifInfo = attachment;
            if (!gifInfo.staticThumbnail) continue;
            CGFloat aspectRatio = gifInfo.staticThumbnail.size.width / gifInfo.staticThumbnail.size.height;
            int newWidth  = (int)(200 * aspectRatio);
            int newHeight = 200;
            if (newWidth > tableWidth - 66) {
                newWidth  = tableWidth - 66;
                newHeight = newWidth / aspectRatio;
            }
            attachmentHeight += newHeight;
        } else if ([attachment isKindOfClass:[NSArray class]]) {
            NSArray *dimensions = attachment;
            if (dimensions.count == 2) {
                int width  = [dimensions[0] intValue];
                int height = [dimensions[1] intValue];
                if (width <= 0 || height <= 0) continue;
                CGFloat aspectRatio = (CGFloat)width / height;
                int newWidth  = 200 * aspectRatio;
                int newHeight = 200;
                if (newWidth > tableWidth - 66) {
                    newWidth  = tableWidth - 66;
                    newHeight = newWidth / aspectRatio;
                }
                attachmentHeight += newHeight;
            }
        }
    }
    // NSLog(@"[Height] snowflake:%@ isGrouped:%d contentHeight:%.0f authorNameHeight:%.0f result:%.0f", 
    //         message.snowflake, message.isGrouped, contentHeight, authorNameSize.height,
    //         contentHeight + attachmentHeight + (attachmentHeight ? 11 : 0));
    return contentHeight + attachmentHeight + (attachmentHeight ? 11 : 0);
}

- (void)attributedLabel:(DTAttributedLabel *)label didSelectLinkWithURL:(NSURL *)url {
    [[UIApplication sharedApplication] openURL:url];
}

- (UIView *)attributedTextContentView:(DTAttributedTextContentView *)attributedTextContentView 
                           viewForLink:(NSURL *)url 
                            identifier:(NSString *)identifier 
                                 frame:(CGRect)frame {
    DTLinkButton *button = [[DTLinkButton alloc] initWithFrame:frame];
    button.URL = url;
    
    if ([[url scheme] isEqualToString:@"discord-spoiler"]) {
        [button addTarget:self 
                   action:@selector(spoilerButtonTapped:) 
         forControlEvents:UIControlEventTouchUpInside];
    } else {
        [button addTarget:self 
                   action:@selector(linkButtonTapped:) 
         forControlEvents:UIControlEventTouchUpInside];
    }
    return button;
}

- (UIView *)attributedTextContentView:(DTAttributedTextContentView *)attributedTextContentView
                    viewForAttachment:(DTTextAttachment *)attachment
                                frame:(CGRect)frame {
    if (![attachment isKindOfClass:[DTImageTextAttachment class]]) return nil;

    DTImageTextAttachment *imageAttachment = (DTImageTextAttachment *)attachment;
    NSURL *url = imageAttachment.contentURL;
    if (![[url scheme] isEqualToString:@"discord-emoji"]) return nil;

    DCEmoji *emoji = [DCServerCommunicator.sharedInstance emojiForSnowflake:url.host];

    CGRect emojiFrame = frame;
    emojiFrame.origin.y += 3.0f;
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:emojiFrame];
    imageView.contentMode  = UIViewContentModeScaleAspectFit;
    if (emoji.image && emoji.image.size.width > 0) {
        imageView.image = emoji.image;
    }
    return imageView;
}

- (void)emojiImageReady:(NSNotification *)notification {
    // Refresh visible cells that have attachment runs so they pick up
    // the newly loaded emoji image via viewForAttachment:frame:
    for (UITableViewCell *cell in self.chatTableView.visibleCells) {
        if (![cell isKindOfClass:[DCChatTableCell class]]) continue;
        DCChatTableCell *chatCell = (DCChatTableCell *)cell;
        if (!chatCell.contentTextView.attributedString) continue;

        __block BOOL hasAttachment = NO;
        [chatCell.contentTextView.attributedString
            enumerateAttribute:NSAttachmentAttributeName
                       inRange:NSMakeRange(0, chatCell.contentTextView.attributedString.length)
                       options:0
                    usingBlock:^(id value, NSRange range, BOOL *stop) {
                        if (value) { hasAttachment = YES; *stop = YES; }
                    }];

        if (hasAttachment) {
            [chatCell.contentTextView removeAllCustomViews];
            [chatCell.contentTextView relayoutText];
        }
    }
}

- (void)linkButtonTapped:(DTLinkButton *)button {
    NSURL *url = button.URL;
    NSString *scheme = url.scheme;
    
    if ([scheme isEqualToString:@"discord-user"]) {
        NSString *snowflake = url.host;
        DCUser *user = [DCServerCommunicator.sharedInstance userForSnowflake:snowflake];
        if (user) {
            [self openUserProfile:user];
        }
    } else if ([scheme isEqualToString:@"discord-channel"]) {
        NSString *snowflake = url.host;
        DCChannel *channel = [DCServerCommunicator.sharedInstance.channels objectForKey:snowflake];
        if (channel) {
            [self navigateToChannel:channel];
        }
    } else if ([scheme isEqualToString:@"discord-role"]) {
        // Role taps — no action for now
    } else if ([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"]) {
        // Check for Discord channel deep link
        if ([[url host] isEqualToString:@"discord.com"] &&
            [[url path] hasPrefix:@"/channels/"]) {
            NSArray *components = [url.path componentsSeparatedByString:@"/"];
            // path is /channels/{guild_id}/{channel_id}
            // components: [@"", @"channels", @"{guild_id}", @"{channel_id}"]
            if (components.count >= 4) {
                NSString *channelId = components[3];
                DCChannel *channel = [DCServerCommunicator.sharedInstance.channels 
                    objectForKey:channelId];
                if (channel) {
                    [self navigateToChannel:channel];
                    return;
                }
            } else if (components.count == 3) {
                NSString *guildId = components[2];
                DCGuild *guild = nil;
                for (DCGuild *g in DCServerCommunicator.sharedInstance.guilds) {
                    if ([g.snowflake isEqualToString:guildId]) {
                        guild = g;
                        break;
                    }
                }
                if (guild) {
                    [self navigateToGuild:guild];
                    return;
                }
            }
        }
        [[UIApplication sharedApplication] openURL:url];
    } else {
        [[UIApplication sharedApplication] openURL:url];
    }
}

- (void)spoilerButtonTapped:(DTLinkButton *)button {
    // Find which cell contains this button
    UIView *view = button.superview;
    while (view && ![view isKindOfClass:[DCChatTableCell class]]) {
        view = view.superview;
    }
    if (!view) return;
    DCChatTableCell *cell = (DCChatTableCell *)view;
    
    // Get the attributed string and find the spoiler range
    NSMutableAttributedString *mutable = [cell.contentTextView.attributedString mutableCopy];
    if (!mutable) return;
    
    // Walk the attributed string looking for DTLinkAttribute matching this URL
    [mutable enumerateAttribute:DTLinkAttribute
                        inRange:NSMakeRange(0, mutable.length)
                        options:0
                     usingBlock:^(id value, NSRange range, BOOL *stop) {
        if (![value isKindOfClass:[NSURL class]]) return;
        NSURL *linkURL = (NSURL *)value;
        if (![[linkURL absoluteString] isEqualToString:[button.URL absoluteString]]) return;
        
        // Apply revealed style to this range
        [[DCMarkdownParser sharedParser] applyBackgroundStyle:DCMarkdownBackgroundStyleSpoilerRevealed
                                                      toRange:range
                                                     inString:mutable
                                                overrideColor:nil];
        // Remove the link so it can't be tapped again
        [mutable removeAttribute:DTLinkAttribute range:range];
        [mutable removeAttribute:DCMarkdownSpoilerAttributeName range:range];
        
        *stop = YES;
    }];
    
    // Update the label with the revealed attributed string
    cell.contentTextView.attributedString = mutable;
    [cell.contentTextView relayoutText];
}

- (void)profileImageTapped:(UITapGestureRecognizer *)recognizer {
    UIView *view = recognizer.view.superview;
    while (view && ![view isKindOfClass:[DCChatTableCell class]]) {
        view = view.superview;
    }
    if (!view) return;

    NSIndexPath *indexPath = [self.chatTableView indexPathForCell:(DCChatTableCell *)view];
    if (!indexPath) return;

    DCMessage *message = [self.messages objectAtIndex:indexPath.row];
    if (!message.author) return;

    [self openUserProfile:message.author];
}

- (void)openUserProfile:(DCUser *)user {
    if (!user) return;
    self.selectedMessage = [[DCMessage alloc] init];
    self.selectedMessage.author = user;
    [self performSegueWithIdentifier:@"chat to contact" sender:self];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    DCMessage *messageAtRowIndex = [self.messages objectAtIndex:indexPath.row];
    
    // Check if next message is grouped under this one
    BOOL nextMessageIsGrouped = NO;
    if (indexPath.row + 1 < self.messages.count) {
        DCMessage *nextMessage = [self.messages objectAtIndex:indexPath.row + 1];
        nextMessageIsGrouped = nextMessage.isGrouped;
    }

    BOOL hasUnloadedAttachments = NO;
    for (id attachment in messageAtRowIndex.attachments) {
        if ([attachment isKindOfClass:[NSArray class]] || 
            ([attachment isKindOfClass:[DCGifInfo class]] && !((DCGifInfo *)attachment).staticThumbnail)) {
            hasUnloadedAttachments = YES;
            break;
        }
    }

    CGFloat currentWidth = self.chatTableView.bounds.size.width;
    NSString *cacheKey = nextMessageIsGrouped 
        ? [messageAtRowIndex.snowflake stringByAppendingString:@"_hasGrouped"]
        : messageAtRowIndex.snowflake;
    
    if (!hasUnloadedAttachments) {
        DCMessageCacheEntry *cached = [[DCCacheManager sharedInstance] 
            cacheEntryForSnowflake:cacheKey width:currentWidth];
        if (cached) return cached.cellHeight;
    }
    
    CGFloat result = [self calculateHeightForMessage:messageAtRowIndex 
                                          tableWidth:currentWidth 
                                    followedByGrouped:nextMessageIsGrouped];
    
    if (!hasUnloadedAttachments) {
        DCMessageCacheEntry *entry = [[DCCacheManager sharedInstance] 
            cacheEntryForSnowflake:cacheKey width:currentWidth] ?: [DCMessageCacheEntry new];
        entry.cellHeight = result;
        [[DCCacheManager sharedInstance] setCacheEntry:entry 
                                          forSnowflake:cacheKey 
                                                 width:currentWidth];
    }
//    NSLog(@"[Height] snowflake: %@ contentHeight: %f attachmentHeight: %d result: %f", 
//    messageAtRowIndex.snowflake, messageAtRowIndex.contentHeight, attachmentHeight, result);
    NSLog(@"[Height] snowflake: %@ result: %.0f textHeight: %.0f",
        messageAtRowIndex.snowflake,
        result,
        messageAtRowIndex.textHeight);
    return result;
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
        [messageActionSheet showFromRect:self.toolbar.frame inView:self.view animated:YES];
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
        [messageActionSheet showFromRect:self.toolbar.frame inView:self.view animated:YES];
    }
}

- (void)actionSheet:(UIActionSheet *)popup
    clickedButtonAtIndex:(NSInteger)buttonIndex {
    if ([popup tag] == 1) {
        if (buttonIndex == 0) {
            UIAlertView *confirmAlert = [[UIAlertView alloc]
                initWithTitle:@"Delete Message"
                      message:@"Are you sure you want to delete this message?"
                     delegate:self
            cancelButtonTitle:@"Cancel"
            otherButtonTitles:@"Delete", nil];
            [confirmAlert show];
        } else if (buttonIndex == 1) {
            if (self.editingMessage
                && [self.editingMessage.snowflake
                    isEqualToString:self.selectedMessage.snowflake]) {
                self.editingMessage               = nil;
                self.inputField.text              = @"";
                self.inputFieldPlaceholder.hidden = NO;
                [self resizeInputField];
            } else {
                self.editingMessage               = self.selectedMessage;
                self.inputField.text              = self.selectedMessage.content;
                self.inputFieldPlaceholder.hidden = YES;
                [self resizeInputField];
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

- (void)resizeInputField {
    static const CGFloat kMaxLines_iPhone  = 5.0f;
    static const CGFloat kMaxLines_iPad    = 10.0f;
    static const CGFloat kSingleLineHeight = 34.0f;

    CGFloat lineHeight     = self.inputField.font.lineHeight;
    CGFloat maxLines       = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
                                 ? kMaxLines_iPad : kMaxLines_iPhone;
    CGFloat maxInputHeight = kSingleLineHeight + ((maxLines - 1) * lineHeight);

    CGFloat desiredHeight = ceilf([self.inputField sizeThatFits:
        CGSizeMake(self.inputField.frame.size.width, MAXFLOAT)].height);

    BOOL needsScroll = (desiredHeight > maxInputHeight);
    self.inputField.scrollEnabled = needsScroll;

    CGFloat newInputHeight   = MAX(MIN(desiredHeight, maxInputHeight), _baseInputHeight);
    CGFloat newToolbarHeight = _baseToolbarHeight + (newInputHeight - _baseInputHeight);
    CGFloat growth           = newToolbarHeight - _baseToolbarHeight;

    // Reset to single line
    if (desiredHeight <= kSingleLineHeight) {
        self.inputField.scrollEnabled = NO;

        CGRect bgFrame      = self.messageFieldBG.frame;
        bgFrame.size.height = _baseMsgFieldBGHeight;
        self.messageFieldBG.frame = bgFrame;

        CGRect inputFrame      = self.inputField.frame;
        inputFrame.size.height = _baseInputHeight;
        inputFrame.origin.y    = _baseInputOriginY;
        self.inputField.frame  = inputFrame;

        CGRect toolbarFrame      = self.toolbar.frame;
        toolbarFrame.size.height = _baseToolbarHeight;
        toolbarFrame.origin.y    = self.view.bounds.size.height
                                   - self.keyboardHeight - _baseToolbarHeight;
        self.toolbar.frame = toolbarFrame;

        CGFloat typingOffset = (self.typingUsers.count > 0) ? 20.0f : 0.0f;
        [self.chatTableView setHeight:self.view.bounds.size.height
                                      - self.keyboardHeight
                                      - _baseToolbarHeight
                                      - typingOffset];
        if (self.typingUsers.count > 0) {
            [self.typingIndicatorView setY:self.view.bounds.size.height
                                           - self.keyboardHeight
                                           - _baseToolbarHeight - 20.0f];
        }
        return;
    }

    CGRect bgFrame      = self.messageFieldBG.frame;
    bgFrame.size.height = _baseMsgFieldBGHeight + growth;
    self.messageFieldBG.frame = bgFrame;

    CGRect inputFrame      = self.inputField.frame;
    inputFrame.size.height = newInputHeight;
    CGFloat bgMidY         = bgFrame.origin.y + bgFrame.size.height / 2.0f;
    inputFrame.origin.y    = bgMidY - newInputHeight / 2.0f;
    self.inputField.frame  = inputFrame;

    if (needsScroll) {
        [self.inputField scrollRangeToVisible:NSMakeRange(self.inputField.text.length, 0)];
    }

    CGRect toolbarFrame      = self.toolbar.frame;
    toolbarFrame.size.height = newToolbarHeight;
    toolbarFrame.origin.y    = self.view.bounds.size.height
                               - self.keyboardHeight - newToolbarHeight;
    self.toolbar.frame = toolbarFrame;

    CGFloat typingOffset = (self.typingUsers.count > 0) ? 20.0f : 0.0f;
    [self.chatTableView setHeight:self.view.bounds.size.height
                                  - self.keyboardHeight
                                  - newToolbarHeight
                                  - typingOffset];
    if (self.typingUsers.count > 0) {
        [self.typingIndicatorView setY:self.view.bounds.size.height
                                       - self.keyboardHeight
                                       - newToolbarHeight - 20.0f];
    }
}

- (void)keyboardWillShow:(NSNotification *)notification {
    // thx to Pierre Legrain
    // http://pyl.io/2015/08/17/animating-in-sync-with-ios-keyboard/
    CGRect keyboardFrame = [[notification.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    // Convert to view coordinates — critical for iPad landscape
    CGRect keyboardFrameInView = [self.view convertRect:keyboardFrame fromView:nil];
    // Only the portion that actually overlaps the view bottom
    self.keyboardHeight = MAX(0, self.view.bounds.size.height - keyboardFrameInView.origin.y);
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
    UIView *v = touch.view;
    while (v) {
        if (v == self.toolbar) return NO;
        v = v.superview;
    }
    return YES;
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
            self.inputField.scrollEnabled = NO;
            [self resizeInputField];
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
    self.selectedImageURL = ((UILazyImageView *)sender.view).imageURL;
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
        DCChatVideoAttachment *video = (DCChatVideoAttachment *)sender.view.superview;

        // YouTube (or any embed with a linkURL): open in browser / YouTube app
        if (video.linkURL) {
            [[UIApplication sharedApplication] openURL:video.linkURL];
            return;
        }

        // All other video embeds — play inline
        NSURL *url = video.videoURL;
        MPMoviePlayerViewController *player = [[MPMoviePlayerViewController alloc] initWithContentURL:url];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(moviePlaybackDidFinish:)
                                                     name:MPMoviePlayerPlaybackDidFinishNotification
                                                   object:player.moviePlayer];
        player.moviePlayer.repeatMode = MPMovieRepeatModeOne;
        UIWindow *backgroundWindow    = [UIApplication sharedApplication].keyWindow;
        player.view.frame             = backgroundWindow.frame;
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
            imageViewController.fullResURL = self.selectedImageURL;
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
        
    // Dismiss existing popover if already showing
    if (self.imagePopoverController.popoverVisible) {
        [self.imagePopoverController dismissPopoverAnimated:YES];
        self.imagePopoverController = nil;
        return;
    }

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

            if ([sender isKindOfClass:[UIButton class]]) {
                // Use the button's view for popover presentation
                UIButton *button = (UIButton *)sender;
                [popoverController
                    presentPopoverFromRect:button.bounds
                                    inView:button
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
            [imageSourceActionSheet showFromRect:self.toolbar.frame inView:self.view animated:YES];
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

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1) {
        [DCServerCommunicator.sharedInstance.selectedChannel deleteMessage:self.selectedMessage];
    }
}

// - (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
//                                 duration:(NSTimeInterval)duration {
//     // Heights already precalculated for both orientations — just reload
//     [self.chatTableView reloadData];
// }

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.chatTableView reloadData];
    });
}

- (void)navigateToChannel:(DCChannel *)channel {
    if (!channel) return;
    
    DCServerCommunicator.sharedInstance.selectedChannel = channel;
    
    // Update DCMenuViewController state without seguing
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"CHANNEL_CONTEXT_CHANGED"
                      object:nil
                    userInfo:@{@"channelId": channel.snowflake}];
    
    // Swap chat in place
    [[NSNotificationCenter defaultCenter] postNotificationName:@"NUKE CHAT DATA" object:nil];
    self.navigationItem.title = channel.type == 0 
        ? [@"#" stringByAppendingString:channel.name] 
        : channel.name;
    self.viewingPresentTime = YES;
    [self getMessages:50 beforeMessage:nil];
}

- (void)navigateToGuild:(DCGuild *)guild {
    if (!guild) return;
    
    // Tell DCMenuViewController to switch to this guild
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"NAVIGATE_TO_GUILD"
                      object:nil
                    userInfo:@{@"guildId": guild.snowflake}];
    
    // Pop back to menu
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    if (![self isMovingFromParentViewController]) {
        return;
    }

    DCServerCommunicator.sharedInstance.selectedChannel = nil;
    [NSNotificationCenter.defaultCenter postNotificationName:@"ChannelSelectionCleared" object:nil];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];

    [[DCCacheManager sharedInstance] handleMemoryWarning];
    for (DCMessage *message in self.messages) {
        message.attributedContent = nil;
    }
    NSLog(@"[DCChatViewController] Memory warning! Freed attributed content");
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
