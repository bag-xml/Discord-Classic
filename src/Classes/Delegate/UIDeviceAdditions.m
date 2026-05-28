//
//  UIDeviceAdditions.m
//
//  Created by Giulio Petek on 19.07.10.
//  Copyright 2010 BigRedSofa. All rights reserved.
//
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#import "UIDeviceAdditions.h"
#include <sys/sysctl.h>  
#include <mach/mach.h>

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

@implementation UIDevice (UIDeviceAdditions)

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

- (void)currentMemoryUsage {
        mach_port_t host_port;
    mach_msg_type_number_t host_size;
    vm_size_t pagesize;

    host_port = mach_host_self();
    host_size = sizeof(vm_statistics_data_t) / sizeof(integer_t);
    host_page_size(host_port, &pagesize);        

    vm_statistics_data_t vm_stat;

    if (host_statistics(host_port, HOST_VM_INFO, (host_info_t)&vm_stat, &host_size) != KERN_SUCCESS) {
        NSLog(@"Failed to fetch vm statistics");
    }

    /* Stats in bytes */ 
    natural_t mem_used = (vm_stat.active_count +
                          vm_stat.inactive_count +
                          vm_stat.wire_count) * pagesize;
    natural_t mem_free = vm_stat.free_count * pagesize;
    natural_t mem_total = mem_used + mem_free;
    NSLog(@"used: %u free: %u total: %u", mem_used, mem_free, mem_total);
}

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

@end