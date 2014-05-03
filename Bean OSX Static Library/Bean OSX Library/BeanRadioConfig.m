//
//  BeanRadioConfig.m
//  Bean OSX Library
//
//  Created by Matthew Chung on 4/29/14.
//  Copyright (c) 2014 Punch Through Design. All rights reserved.
//

#import "BeanRadioConfig.h"
#import "Bean.h"

@interface BeanRadioConfig()
@end

@implementation BeanRadioConfig

-(BOOL)validate:(NSError**)error {
    if (self.name.length>20) {
        if (error) {
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey : NSLocalizedString(@"Name length can not exceed 20 characters", @"")};
            *error = [NSError errorWithDomain:BeanInvalidArgurment code:0 userInfo:userInfo];
        }
        return NO;
    }
    else if (self.connectionInterval <= 0) {
        if (error) {
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey : NSLocalizedString(@"Connection interval must be >0 and less than ???", @"")};
            *error = [NSError errorWithDomain:BeanInvalidArgurment code:0 userInfo:userInfo];
        }
        return NO;
    }
    else if (self.advertisingInterval <= 0) {
        if (error) {
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey : NSLocalizedString(@"Advertising interval must be >0 and less than ???", @"")};
            *error = [NSError errorWithDomain:BeanInvalidArgurment code:0 userInfo:userInfo];
        }
        return NO;
    }
    return YES;
}
@end