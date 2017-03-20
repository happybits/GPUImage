//
//  FilterConfiguration.m
//  Marco Polo
//
//  Created by Dave Walker on 3/17/17.
//  Copyright © 2017 Happy Bits. All rights reserved.
//

#import "FilterConfiguration.h"
#import "BeautifyFilter.h"
#import "AutoExposureAdjustment.h"

@interface FilterConfiguration()

@property (nonatomic, strong) Camera *camera;
@property (nonatomic, assign) NSTimeInterval startTime;

@property (nonatomic, readwrite) NSString *configName;

@end

@implementation FilterConfiguration

- (instancetype)init {
    if (self = [super init]) {
        _camera = [Camera new];
        _configName = @"Filter Test";
    }

    return self;
}

- (void)startCamera {

    if (self.includeCameraRender) {
        GPUImageOutput *current = self.camera.cameraAdapter;

        if (self.includeExposureAdjust) {
            GPUImageExposureFilter *exposureFilter = [[GPUImageExposureFilter alloc] init];
            AutoExposureAdjustment *exposureAdjustment = [[AutoExposureAdjustment alloc] initWithExposureFilter:exposureFilter];

            [current addTarget:exposureFilter];
            [current addTarget:exposureAdjustment];
            current = exposureFilter;
        }

        if (self.includeBeautify) {
            BeautifyFilter *beautifyFilter = [BeautifyFilter new];
            [current addTarget:beautifyFilter];
            current = beautifyFilter;
        }

        if (self.includePreview) {
            [current addTarget:self.preview];
            self.preview.useVbo = YES;
        }

    } else {
        self.camera.cameraAdapter.textureRenderDisabled = YES;
    }


    [self.camera start];
    self.startTime = CACurrentMediaTime();
}

- (void)resetStats {
    [self.camera resetFrameCounters];
    self.startTime = CACurrentMediaTime();
}

- (float)cpuUsage {
    NSTimeInterval elapsedTime = CACurrentMediaTime() - self.startTime;
    FrameCounters counters = [self.camera getFrameCounters];
    return 100.f * ((float)counters.processingTime / elapsedTime);
}

- (FrameCounters)counters {
    return [self.camera getFrameCounters];
}

@end
