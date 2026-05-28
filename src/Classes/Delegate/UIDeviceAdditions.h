//
//  UIDeviceAdditions.h
//
//  Created by Giulio Petek on 19.07.10.
//  Copyright 2010 BigRedSofa. All rights reserved.
//
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#import <UIKit/UIKit.h>

@interface UIDevice (UIDeviceAdditions)

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

// Returns the amount of memory which is currently used (in MB).
@property (readonly) void currentMemoryUsage; 

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

@end