//
//  main.m
//  Discord Classic
//
//  Created by bag.xml on 3/2/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DCAppDelegate.h"

int main(int argc, char *argv[]) {
#ifdef DEBUG
    setenv("NSZombieEnabled", "YES", 1);
    setenv("NSDeallocateZombies", "YES", 1);
    setenv("MallocStackLogging", "1", 1);
    setenv("MallocStackLoggingNoCompact", "1", 1);
    setenv("NSAutoreleaseFreedObjectCheckEnabled", "YES", 1);
#endif
    @autoreleasepool {
        return UIApplicationMain(
            argc,
            argv,
            nil,
            NSStringFromClass([DCAppDelegate class])
        );
    }
}
