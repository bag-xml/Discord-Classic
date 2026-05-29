//
//  DCImageViewController.m
//  Discord Classic
//
//  Created by Trevir on 11/17/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import "DCImageViewController.h"

@interface DCImageViewController ()

@end

@implementation DCImageViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.slideMenuController.gestureSupport = NO;

    self.scrollView.delegate         = self;
    self.scrollView.minimumZoomScale = 1.0;
    self.scrollView.maximumZoomScale = 4.0;
    self.scrollView.zoomScale        = 1.0;
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
    // @available doesn't exist on iOS 5, use NSClassFromString instead
    if (NSClassFromString(@"UIActivityViewController")) {
        // Show share sheet with appropriate options
        NSArray *itemsToShare = @[ self.imageView.image ];
        UIActivityViewController *activityVC =
            [[UIActivityViewController alloc] initWithActivityItems:itemsToShare
                                              applicationActivities:nil];
        [activityVC viewWillAppear:YES];
        [self presentViewController:activityVC animated:YES completion:nil];
        [activityVC viewWillAppear:YES];
    }
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}

@end
