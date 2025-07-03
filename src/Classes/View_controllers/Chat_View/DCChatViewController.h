//
//  DCChatViewController.h
//  Discord Classic
//
//  Created by bag.xml on 3/6/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import <AssetsLibrary/AssetsLibrary.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import "APLSlideMenuViewController.h"
#import "DCChannel.h"
#import "DCContactViewController.h"
#import "DCMessage.h"
#import "ODCContactViewController.h"
@interface DCChatViewController : UIViewController<
                                      UINavigationControllerDelegate,
                                      UITextViewDelegate,
                                      UITableViewDataSource,
                                      UITableViewDelegate,
                                      UIImagePickerControllerDelegate,
                                      UIActionSheetDelegate>
- (void)getMessages:(int)numberOfMessages beforeMessage:(DCMessage *)message;

@property (weak, nonatomic) IBOutlet UIToolbar *toolbar;
@property (weak, nonatomic) IBOutlet UITableView *chatTableView;
@property (weak, nonatomic) IBOutlet UITextView *inputField;
@property (weak, nonatomic) IBOutlet UILabel *inputFieldPlaceholder;
@property (weak, nonatomic) IBOutlet UIView *inputView;

@property (weak, nonatomic) IBOutlet UINavigationBar *nbbar;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *nbmodaldone;

// buttons
@property (weak, nonatomic) IBOutlet UIBarButtonItem *memberButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *sendButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *photoButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *sidebarButton;

@property bool viewingPresentTime;

@property DCMessage *selectedMessage;

@property NSMutableArray *messages;

@property (nonatomic, strong) UIPopoverController *imagePopoverController;


@end
