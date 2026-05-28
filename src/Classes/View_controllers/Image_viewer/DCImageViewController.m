//
//  DCImageViewController.m
//  Discord Classic
//
//  Created by Trevir on 11/17/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import "DCImageViewController.h"
#include "SDWebImageManager.h"
#import "DCTools.h"

@interface DCImageViewController ()

@end

@implementation DCImageViewController

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.scrollView.frame = self.view.bounds;
    self.navBar.alpha = 1.0;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.slideMenuController.gestureSupport = NO;

    self.scrollView.delegate         = self;
    self.scrollView.minimumZoomScale = 1.0;
    self.scrollView.maximumZoomScale = 4.0;
    self.scrollView.zoomScale        = 1.0;
    self.scrollView.clipsToBounds    = YES;
    self.scrollView.backgroundColor  = [UIColor blackColor];

    // Extend under status bar
    self.wantsFullScreenLayout = YES;
    if ([[UIDevice currentDevice] userInterfaceIdiom] != UIUserInterfaceIdiomPad) {
        [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackTranslucent animated:YES];
    }

    // Double tap to zoom
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [self.scrollView addGestureRecognizer:doubleTap];

    // Single tap to toggle chrome
    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleSingleTap:)];
    singleTap.numberOfTapsRequired = 1;
    [singleTap requireGestureRecognizerToFail:doubleTap];
    [self.scrollView addGestureRecognizer:singleTap];

    self.chromeVisible = YES;

    if (self.fullResURL) {
        NSString *urlString = self.fullResURL.absoluteString;
        
        // Split URL into base and query
        NSRange queryRange = [urlString rangeOfString:@"?"];
        if (queryRange.location != NSNotFound) {
            NSString *base = [urlString substringToIndex:queryRange.location + 1];
            NSString *query = [urlString substringFromIndex:queryRange.location + 1];
            
            // Filter out width and height params
            NSArray *params = [query componentsSeparatedByString:@"&"];
            NSMutableArray *filteredParams = [NSMutableArray array];
            for (NSString *param in params) {
                if (![param hasPrefix:@"width="] && ![param hasPrefix:@"height="]) {
                    [filteredParams addObject:param];
                }
            }
            urlString = [base stringByAppendingString:[filteredParams componentsJoinedByString:@"&"]];
        }
        
        NSURL *fullResURL = [NSURL URLWithString:urlString];
        NSLog(@"[ImageViewer] full res URL: %@", fullResURL);
        
        SDWebImageManager *manager = [SDWebImageManager sharedManager];
        __weak DCImageViewController *weakSelf = self;
        [manager downloadImageWithURL:fullResURL
                              options:SDWebImageRefreshCached
                             progress:nil
                            completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                if (image && finished) {
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        DCImageViewController *strongSelf = weakSelf;
                                        if (!strongSelf) return; // view controller was deallocated
                                        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
                                        strongSelf.imageView.image = image;
                                    });
                                } else {
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
                                    });
                                }
                            }];
    }
}

- (void)handleSingleTap:(UITapGestureRecognizer *)recognizer {
    self.chromeVisible = !self.chromeVisible;
    [UIView animateWithDuration:0.3 animations:^{
        [[UIApplication sharedApplication] setStatusBarHidden:!self.chromeVisible
                                                withAnimation:UIStatusBarAnimationFade];
        self.navBar.alpha = self.chromeVisible ? 1.0 : 0.0;
    }];
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)recognizer {
    if (self.scrollView.zoomScale > self.scrollView.minimumZoomScale) {
        // Already zoomed in — zoom back out
        [self.scrollView setZoomScale:self.scrollView.minimumZoomScale animated:YES];
    } else {
        // Zoom in centered on tap point
        CGPoint tapPoint = [recognizer locationInView:self.imageView];
        CGFloat newScale = self.scrollView.maximumZoomScale;
        CGFloat width    = self.scrollView.bounds.size.width / newScale;
        CGFloat height   = self.scrollView.bounds.size.height / newScale;
        CGRect zoomRect  = CGRectMake(tapPoint.x - width / 2,
                                      tapPoint.y - height / 2,
                                      width, height);
        [self.scrollView zoomToRect:zoomRect animated:YES];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [UIView animateWithDuration:0.15 animations:^{
        self.navBar.alpha = 0.0;
    }];
    if ([[UIDevice currentDevice] userInterfaceIdiom] != UIUserInterfaceIdiomPad) {
        [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:YES];
        [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
    }
}

- (void)viewDidUnload {
    [self setImageView:nil];
    [self setScrollView:nil];
    [super viewDidUnload];
}

- (IBAction)done:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)presentShareSheet:(id)sender {
    if (NSClassFromString(@"UIActivityViewController")) {
        // iOS 6+ share sheet
        NSArray *itemsToShare = @[self.imageView.image];
        UIActivityViewController *activityVC = [[UIActivityViewController alloc]
            initWithActivityItems:itemsToShare
            applicationActivities:nil];
        [self presentViewController:activityVC animated:YES completion:nil];
    } else {
        // iOS 5 — action sheet with manual options
        UIActionSheet *sheet = [[UIActionSheet alloc]
            initWithTitle:nil
                 delegate:self
        cancelButtonTitle:@"Cancel"
   destructiveButtonTitle:nil
        otherButtonTitles:@"Save to Camera Roll", @"Copy Image", @"Print", @"Email", @"Message", nil];
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
            UIView *shareView = [self.share valueForKey:@"view"];
            if (shareView) {
                [sheet showFromRect:shareView.bounds inView:shareView animated:YES];
            } else {
                [sheet showInView:self.view];
            }
        } else {
            [sheet showInView:self.view];
        }
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    switch (buttonIndex) {
        case 0: // Save to Camera Roll
            UIImageWriteToSavedPhotosAlbum(self.imageView.image, self,
                @selector(image:didFinishSavingWithError:contextInfo:), nil);
            break;
        case 1: // Copy
            [[UIPasteboard generalPasteboard] setImage:self.imageView.image];
            [DCTools alert:@"Copied" withMessage:@"Image copied to clipboard."];
            break;
        case 2: // Print
            if ([UIPrintInteractionController isPrintingAvailable]) {
                UIPrintInteractionController *printer = [UIPrintInteractionController sharedPrintController];
                UIPrintInfo *printInfo = [UIPrintInfo printInfo];
                printInfo.outputType = UIPrintInfoOutputPhoto;
                printer.printInfo = printInfo;
                printer.printingItem = self.imageView.image;
                [printer presentAnimated:YES completionHandler:nil];
            } else {
                [DCTools alert:@"Unavailable" withMessage:@"Printing is not available on this device."];
            }
            break;
        case 3: // Email
            if ([MFMailComposeViewController canSendMail]) {
                MFMailComposeViewController *mail = [MFMailComposeViewController new];
                mail.mailComposeDelegate = self;
                NSData *imageData = UIImagePNGRepresentation(self.imageView.image);
                [mail addAttachmentData:imageData mimeType:@"image/png" fileName:@"image.png"];
                [self presentViewController:mail animated:YES completion:nil];
            } else {
                [DCTools alert:@"Unavailable" withMessage:@"Mail is not configured on this device."];
            }
            break;
        case 4: // Message
            if ([MFMessageComposeViewController canSendText] && 
                [MFMessageComposeViewController canSendAttachments]) {
                MFMessageComposeViewController *message = [MFMessageComposeViewController new];
                message.messageComposeDelegate = self;
                NSData *imageData = UIImagePNGRepresentation(self.imageView.image);
                [message addAttachmentData:imageData typeIdentifier:@"public.png" filename:@"image.png"];
                [self presentViewController:message animated:YES completion:nil];
            } else {
                [DCTools alert:@"Unavailable" withMessage:@"Messages is not available on this device."];
            }
            break;
        default:
            break;
    }
}

- (void)mailComposeController:(MFMailComposeViewController *)controller
          didFinishWithResult:(MFMailComposeResult)result
                        error:(NSError *)error {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)messageComposeViewController:(MFMessageComposeViewController *)controller
                  didFinishWithResult:(MessageComposeResult)result {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// - (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
//     if (buttonIndex == 1) {
//         UIImageWriteToSavedPhotosAlbum(self.imageView.image, self, 
//             @selector(image:didFinishSavingWithError:contextInfo:), nil);
//     }
// }

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    if (error) {
        [DCTools alert:@"Save Failed" withMessage:error.localizedDescription];
    } else {
        [DCTools alert:@"Saved" withMessage:@"Image saved to camera roll."];
    }
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}

@end
