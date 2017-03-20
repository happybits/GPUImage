//
//  Camera.h
//  Marco Polo
//
//  Created by Dave Walker on 3/17/17.
//  Copyright © 2017 Happy Bits. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HBGPUImageCameraAdapter.h"

typedef struct {
    NSUInteger count;
    NSTimeInterval processingTime;
} FrameCounters;

@interface Camera : NSObject

- (void)start;

@property (nonatomic, readonly) HBGPUImageCameraAdapter *cameraAdapter;

- (void)resetFrameCounters;
- (FrameCounters)getFrameCounters;

@end
