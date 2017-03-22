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
{
#define FLTS_CNT 1
    GPUImageOutput<GPUImageInput> * flts[FLTS_CNT];
}

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
            //BeautifyFilter *beautifyFilter = [BeautifyFilter new];
            GPUImageBeautifyFilter *beautifyFilter = [GPUImageBeautifyFilter new];
            flts[0] = beautifyFilter;
            [current addTarget:beautifyFilter];
            current = beautifyFilter;
            
            self.intensity = 0.50;

//            flts[0] = [[GPUImageBeautifyFilter alloc] init];
//            //flts[0] = [[GPUImageBilateralFilter alloc] init];
//            for(int i=0; i<FLTS_CNT; i++) {
//                [(GPUImageBeautifyFilter *)flts[i] setDistanceNormalizationFactor:4.0];
//                [(GPUImageBeautifyFilter *)flts[i] setIntensity:intensity];
//            }
//            [movieFile addTarget:flts[0]];
//            for(int i=1;i<FLTS_CNT;i++) {
//                flts[i] = [[GPUImageBeautifyFilter alloc] init];
//                [flts[i-1] addTarget:flts[i]];
//            }
//            // Only rotate the video for display, leave orientation the same for recording
//            GPUImageView *filterView = (GPUImageView *)self.view;
//            //[filter addTarget:filterView];
//            [flts[FLTS_CNT-1] addTarget:filterView];
            
        }

        if (self.includePreview) {
            [current addTarget:self.preview];
            self.preview.useVbo = NO;
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

- (void)setIntensity:(float)intensity {
    [(GPUImageBeautifyFilter *)flts[0] setIntensity:intensity];
}

@end
