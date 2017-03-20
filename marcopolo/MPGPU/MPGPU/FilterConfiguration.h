//
//  FilterConfiguration.h
//  Marco Polo
//
//  Created by Dave Walker on 3/17/17.
//  Copyright © 2017 Happy Bits. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GPUImage.h"
#import "Camera.h"

@interface FilterConfiguration : NSObject

@property (nonatomic, readonly) NSString *configName;
@property (nonatomic, readonly) float cpuUsage;
@property (nonatomic, readonly) FrameCounters counters;

@property (nonatomic, strong) GPUImageView *preview;
@property (nonatomic, assign) BOOL includeCameraRender;
@property (nonatomic, assign) BOOL includeExposureAdjust;
@property (nonatomic, assign) BOOL includeBeautify;
@property (nonatomic, assign) BOOL includePreview;

- (void)startCamera;
- (void)resetStats;

@end
