#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import "GPUImageContext.h"
#import "GPUImageOutput.h"

/**
 A GPUImageOutput that provides frames from either camera
 */
@interface HBGPUImageCameraAdapter : GPUImageOutput

@property (nonatomic, assign) AVCaptureDevicePosition cameraPosition;
@property (nonatomic, assign) UIInterfaceOrientation outputImageOrientation;

@property (nonatomic, assign) int pixelFormat;
@property (nonatomic, assign) BOOL useVbo;
@property (nonatomic, assign) BOOL textureRenderDisabled;
@property (nonatomic, assign) BOOL reuseFramebuffer;

@property (nonatomic, assign) BOOL horizontallyMirrorFrontFacingCamera;
@property (nonatomic, assign) BOOL horizontallyMirrorRearFacingCamera;
@property (nonatomic, assign) BOOL dropAllFrames;

- (id)init;
- (void)setupConversion:(AVCaptureVideoDataOutput *)videoOutput;
- (void)processSampleBuffer:(CMSampleBufferRef)sampleBuffer andCaptureFilteredImage:(GPUImageOutput *)filter withBlock:(void (^)(UIImage *))block;
- (void)runBlockSynchronously:(void (^)())block;
@end
