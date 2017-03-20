//
//  FTCamera.m
//  Marco Polo
//
//  Created by Dave Walker on 3/17/17.
//  Copyright © 2017 Happy Bits. All rights reserved.
//

#import "Camera.h"
#import <AVFoundation/AVFoundation.h>
#import "GPUImage.h"

@interface Camera() <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic) AVCaptureVideoDataOutput *videoDataOutput;
@property (nonatomic) AVCaptureConnection *videoConnection;
@property (nonatomic) AVCaptureDevice *frontCamera;
@property (nonatomic) AVCaptureDevice *backCamera;
@property (nonatomic) FrameCounters frameCounters;

@property (nonatomic, readwrite) HBGPUImageCameraAdapter *cameraAdapter;

@end

@implementation Camera

- (instancetype)init {

    if (!(self = [super init])) {
        return nil;
    }

    _session = [[AVCaptureSession alloc] init];
    _cameraAdapter = [[HBGPUImageCameraAdapter alloc] init];
    _cameraAdapter.horizontallyMirrorFrontFacingCamera = YES;
    _cameraAdapter.horizontallyMirrorRearFacingCamera = NO;
    _cameraAdapter.outputImageOrientation = UIInterfaceOrientationPortrait;
    _cameraAdapter.cameraPosition = AVCaptureDevicePositionFront;

    // N.B. Using VBO and reusing frame buffers are a performance win.
    _cameraAdapter.useVbo = YES;
    _cameraAdapter.reuseFramebuffer = YES;

    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        switch (device.position) {
            case AVCaptureDevicePositionFront:
                _frontCamera = device;
                break;
            case AVCaptureDevicePositionBack:
                _backCamera = device;
                break;
            default:
                break;
        }
    }

    return self;
}

- (void)start {

    AVCaptureDevice *videoDevice = self.frontCamera;
    NSString *capturePreset = AVCaptureSessionPreset640x480;
    int32_t frameRate = 30;

    [self.session beginConfiguration];
    if ([self.session canSetSessionPreset:capturePreset]) {
        self.session.sessionPreset = capturePreset;
    }

    NSError *error;
    AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    if (error) {
        NSLog(@"Failed to configure video device input");
        [self.session commitConfiguration];
        return;
    }

    if ([self.session canAddInput:videoDeviceInput]) {
        [self.session addInput:videoDeviceInput];
        self.videoDeviceInput = videoDeviceInput;
    } else {
        NSLog(@"Could not add video device input");
        [self.session commitConfiguration];
        return;
    }

    // Setup Outputs

    // N.B. Delivering the camera frame to the main thread for texture processing is
    //      a performance win.
    AVCaptureVideoDataOutput *videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    [videoDataOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];

    [self.session removeOutput:self.videoDataOutput];
    if ([self.session canAddOutput:videoDataOutput]) {
        [self.session addOutput:videoDataOutput];
        self.videoDataOutput = videoDataOutput;
    }

    // Setup output and video connection settings
    // TODO: Why do we not set them inside the if block above? Do they get reset?

    [self.cameraAdapter setupConversion:self.videoDataOutput];
    NSMutableDictionary *videoSettings = [[NSMutableDictionary alloc] init];
    videoSettings[(id)kCVPixelBufferPixelFormatTypeKey] = @(self.cameraAdapter.pixelFormat);

    self.videoDataOutput.videoSettings = videoSettings;
    self.videoDataOutput.alwaysDiscardsLateVideoFrames = YES;

    // Configure the video device. This must happen last for the settings to stick.
    // They can be reset by configuring session inputs and outputs.
    if ([videoDevice lockForConfiguration:&error]) {
        CMTime frameDuration = CMTimeMake(1, frameRate);
        videoDevice.activeVideoMinFrameDuration = frameDuration;
        videoDevice.activeVideoMaxFrameDuration = frameDuration;
        [videoDevice unlockForConfiguration];
    } else {
        NSLog(@"Failed to lock video device to configure");
        [self.session commitConfiguration];
        return;
    }

    [self.session commitConfiguration];
    if (!self.session.isRunning) {
        [self.session startRunning];
    }
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {

    NSTimeInterval startTime = CACurrentMediaTime();
    [self.cameraAdapter processSampleBuffer:sampleBuffer andCaptureFilteredImage:nil withBlock:nil];
    NSTimeInterval frameTime = CACurrentMediaTime() - startTime;
    
    @synchronized (self) {
        FrameCounters counters = self.frameCounters;
        counters.count += 1;
        counters.processingTime += frameTime;
        self.frameCounters = counters;
    }
}

- (void)resetFrameCounters {
    @synchronized (self) {
        memset(&_frameCounters, 0, sizeof(FrameCounters));
    }

}
- (FrameCounters)getFrameCounters {
    @synchronized (self) {
        return self.frameCounters;
    }
}

@end
