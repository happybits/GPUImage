#import "HBGPUImageCameraAdapter.h"
#import "GPUImageMovieWriter.h"
#import "GPUImageFilter.h"

// Color Conversion Constants (YUV to RGB) including adjustment from 16-235/16-240 (video range)

// BT.601, which is the standard for SDTV.
const GLfloat kHBColorConversion601[] = {
    1.164f,  1.164f, 1.164f,
    0.0f, -0.392f, 2.017f,
    1.596f, -0.813f,   0.0f,
};

// BT.709, which is the standard for HDTV.
const GLfloat kHBColorConversion709[] = {
    1.164f,  1.164f, 1.164f,
    0.0f, -0.213f, 2.112f,
    1.793f, -0.533f,   0.0f,
};

// BT.601 full range (ref: http://www.equasys.de/colorconversion.html)
const GLfloat kHBColorConversion601FullRange[] = {
    1.0f,    1.0f,    1.0f,
    0.0f,    -0.343f, 1.765f,
    1.4f,    -0.711f, 0.0f,
};

NSString *const kHBGPUImageYUVVideoRangeConversionForRGFragmentShaderString = SHADER_STRING(
  varying highp vec2 textureCoordinate;
  
  uniform sampler2D luminanceTexture;
  uniform sampler2D chrominanceTexture;
  uniform mediump mat3 colorConversionMatrix;
  uniform highp float exposure;
  
  void main()
  {
      mediump vec3 yuv;
      lowp vec3 rgb;
      
      yuv.x = texture2D(luminanceTexture, textureCoordinate).r;
      yuv.yz = texture2D(chrominanceTexture, textureCoordinate).rg - vec2(0.5, 0.5);
      rgb = colorConversionMatrix * yuv;
      
      gl_FragColor = vec4(rgb * pow(2.0, exposure), 1);
  }
);

NSString *const kHBGPUImageYUVFullRangeConversionForLAFragmentShaderString = SHADER_STRING(
 varying highp vec2 textureCoordinate;
 
 uniform sampler2D luminanceTexture;
 uniform sampler2D chrominanceTexture;
 uniform mediump mat3 colorConversionMatrix;
 uniform highp float exposure;
 
 void main()
 {
     mediump vec3 yuv;
     lowp vec3 rgb;
     
     yuv.x = texture2D(luminanceTexture, textureCoordinate).r;
     yuv.yz = texture2D(chrominanceTexture, textureCoordinate).ra - vec2(0.5, 0.5);
     rgb = colorConversionMatrix * yuv;
     
     gl_FragColor = vec4(rgb * pow(2.0, exposure), 1);
 }
);

NSString *const kHBGPUImageYUVVideoRangeConversionForLAFragmentShaderString = SHADER_STRING(
  varying highp vec2 textureCoordinate;
  
  uniform sampler2D luminanceTexture;
  uniform sampler2D chrominanceTexture;
  uniform mediump mat3 colorConversionMatrix;
  uniform highp float exposure;
  
  void main()
  {
      mediump vec3 yuv;
      lowp vec3 rgb;
      
      yuv.x = texture2D(luminanceTexture, textureCoordinate).r - (16.0/255.0);
      yuv.yz = texture2D(chrominanceTexture, textureCoordinate).ra - vec2(0.5, 0.5);
      rgb = colorConversionMatrix * yuv;
      
      gl_FragColor = vec4(rgb * pow(2.0, exposure), 1);
  }
);

@interface HBGPUImageCameraAdapter () {
    GLuint vertexBuffer;
    GLuint indexBuffer;
    GLuint vao;
}

@property (nonatomic, strong) GLProgram *yuvConversionProgram;
@property (nonatomic, assign) GLint yuvConversionPositionAttribute;
@property (nonatomic, assign) GLint yuvConversionTextureCoordinateAttribute;
@property (nonatomic, assign) GLint yuvConversionLuminanceTextureUniform;
@property (nonatomic, assign) GLint yuvConversionChrominanceTextureUniform;
@property (nonatomic, assign) GLint yuvConversionMatrixUniform;
@property (nonatomic, assign) GLint exposureUniform;
@property (nonatomic, assign) const GLfloat *preferredConversion;
@property (nonatomic, assign) BOOL isFullYUVRange;
@property (nonatomic, assign) int imageBufferWidth;
@property (nonatomic, assign) int imageBufferHeight;
@property (nonatomic, assign) GPUImageRotationMode outputRotation;
@property (nonatomic, assign) GPUImageRotationMode internalRotation;
@property (nonatomic, assign) GLuint luminanceTexture;
@property (nonatomic, assign) GLuint chrominanceTexture;
@property (nonatomic, assign) BOOL thumbNeeded;
@property (nonatomic, assign) CGFloat exposure;

@property (nonatomic, assign) CVOpenGLESTextureRef luminanceTextureRef;
@property (nonatomic, assign) CVOpenGLESTextureRef chrominanceTextureRef;

@end

@implementation HBGPUImageCameraAdapter

- (id)init {
	if (!(self = [super init])) {
		return nil;
    }
    
    _outputRotation = kGPUImageNoRotation;
    _internalRotation = kGPUImageNoRotation;
    _preferredConversion = kHBColorConversion709;
    
	return self;
}

- (void)setupConversion:(AVCaptureVideoDataOutput *)videoOutput {
    
    if ([GPUImageContext supportsFastTextureUpload]) {
        BOOL supportsFullYUVRange = NO;

        // The first formats listed in the available format array are the most efficient. Use whichever
        // format appears first.
        NSArray *supportedPixelFormats = videoOutput.availableVideoCVPixelFormatTypes;
        for (NSNumber *currentPixelFormat in supportedPixelFormats) {
            if (currentPixelFormat.intValue == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
                currentPixelFormat.intValue == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {

                supportsFullYUVRange = currentPixelFormat.intValue == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
                break;
            }
        }
        
        if (supportsFullYUVRange) {
            _pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
        } else {
            _pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
        }
        
        _isFullYUVRange = supportsFullYUVRange;
        if (_isFullYUVRange) {
            self.preferredConversion = kHBColorConversion601FullRange;
        } else {
            self.preferredConversion = kHBColorConversion601;
        }
        
    } else {
        _pixelFormat = kCVPixelFormatType_32BGRA;
    }
    
    runSynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext useImageProcessingContext];
        if (self.isFullYUVRange) {
            self.yuvConversionProgram = [[GPUImageContext sharedImageProcessingContext] programForVertexShaderString:kGPUImageVertexShaderString fragmentShaderString:kHBGPUImageYUVFullRangeConversionForLAFragmentShaderString];
        } else {
            self.yuvConversionProgram = [[GPUImageContext sharedImageProcessingContext] programForVertexShaderString:kGPUImageVertexShaderString fragmentShaderString:kHBGPUImageYUVVideoRangeConversionForLAFragmentShaderString];
        }
        
        if (!self.yuvConversionProgram.initialized) {
            [self.yuvConversionProgram addAttribute:@"position"];
            [self.yuvConversionProgram addAttribute:@"inputTextureCoordinate"];
            
            if (![self.yuvConversionProgram link]) {
                NSString *progLog = [self.yuvConversionProgram programLog];
                NSLog(@"Program link log: %@", progLog);
                NSString *fragLog = [self.yuvConversionProgram fragmentShaderLog];
                NSLog(@"Fragment shader compile log: %@", fragLog);
                NSString *vertLog = [self.yuvConversionProgram vertexShaderLog];
                NSLog(@"Vertex shader compile log: %@", vertLog);
                self.yuvConversionProgram = nil;
                NSAssert(NO, @"Filter shader link failed");
            }
        }
        
        self.yuvConversionPositionAttribute = [self.yuvConversionProgram attributeIndex:@"position"];
        self.yuvConversionTextureCoordinateAttribute = [self.yuvConversionProgram attributeIndex:@"inputTextureCoordinate"];
        self.yuvConversionLuminanceTextureUniform = [self.yuvConversionProgram uniformIndex:@"luminanceTexture"];
        self.yuvConversionChrominanceTextureUniform = [self.yuvConversionProgram uniformIndex:@"chrominanceTexture"];
        self.yuvConversionMatrixUniform = [self.yuvConversionProgram uniformIndex:@"colorConversionMatrix"];
        self.exposureUniform = [self.yuvConversionProgram uniformIndex:@"exposure"];

        [GPUImageContext setActiveShaderProgram:self.yuvConversionProgram];

        if (self.useVbo) {
            [self setupVBOs];
        }

        glUniform1i(self.yuvConversionLuminanceTextureUniform, 4);
        glUniform1i(self.yuvConversionChrominanceTextureUniform, 5);
        glUniformMatrix3fv(self.yuvConversionMatrixUniform, 1, GL_FALSE, self.preferredConversion);
        glUniform1f(self.exposureUniform, 0);
        
        glEnableVertexAttribArray(self.yuvConversionPositionAttribute);
        glEnableVertexAttribArray(self.yuvConversionTextureCoordinateAttribute);
    });
}

- (void)updateExposure:(CGFloat)exposure {
    self.exposure = exposure;

    runAsynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext setActiveShaderProgram:self.yuvConversionProgram];
        glUniform1f(self.exposureUniform, exposure);
    });
}

#pragma mark Managing targets

- (void)addTarget:(id<GPUImageInput>)newTarget atTextureLocation:(NSInteger)textureLocation {
    [super addTarget:newTarget atTextureLocation:textureLocation];
    [newTarget setInputRotation:self.outputRotation atIndex:textureLocation];
}


#define INITIALFRAMESTOIGNOREFORBENCHMARK 5

- (void)updateTargetsForVideoCameraUsingCacheTextureAtWidth:(int)bufferWidth height:(int)bufferHeight time:(CMTime)currentTime {
    // First, update all the framebuffers in the targets
    for (id<GPUImageInput> currentTarget in targets) {
        if ([currentTarget enabled]) {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            if (currentTarget != self.targetToIgnoreForUpdates) {
                [currentTarget setInputRotation:self.outputRotation atIndex:textureIndexOfTarget];
                [currentTarget setInputSize:CGSizeMake(bufferWidth, bufferHeight) atIndex:textureIndexOfTarget];
                
                if ([currentTarget wantsMonochromeInput]) {
                    [currentTarget setCurrentlyReceivingMonochromeInput:YES];
                    // TODO: Replace optimization for monochrome output
                    [currentTarget setInputFramebuffer:outputFramebuffer atIndex:textureIndexOfTarget];
                } else {
                    [currentTarget setCurrentlyReceivingMonochromeInput:NO];
                    [currentTarget setInputFramebuffer:outputFramebuffer atIndex:textureIndexOfTarget];
                }
            } else {
                [currentTarget setInputRotation:self.outputRotation atIndex:textureIndexOfTarget];
                [currentTarget setInputFramebuffer:outputFramebuffer atIndex:textureIndexOfTarget];
            }
        }
    }
    
    // Then release our hold on the local framebuffer to send it back to the cache as soon as it's no longer needed
    if (!self.reuseFramebuffer) {
        [outputFramebuffer unlock];
        outputFramebuffer = nil;
    }
    
    // Finally, trigger rendering as needed
    for (id<GPUImageInput> currentTarget in targets){
        if ([currentTarget enabled]) {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            if (currentTarget != self.targetToIgnoreForUpdates) {
                [currentTarget newFrameReadyAtTime:currentTime atIndex:textureIndexOfTarget];
            }
        }
    }
}

- (void)processSampleBuffer:(CMSampleBufferRef)sampleBuffer
    andCaptureFilteredImage:(GPUImageOutput *)filter
                  withBlock:(void (^)(UIImage *))block {

    if (self.dropAllFrames) {
        return;
    }
    
    if (filter) {
        [filter useNextFrameForImageCapture];
    }
    
    [self processVideoSampleBuffer:sampleBuffer];

    if (block) {
        UIImage *capturedImage = [filter imageFromCurrentFramebuffer];
        block(capturedImage);
    }
}

- (void)processVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CVImageBufferRef cameraFrame = CMSampleBufferGetImageBuffer(sampleBuffer);
    int bufferWidth = (int)CVPixelBufferGetWidth(cameraFrame);
    int bufferHeight = (int)CVPixelBufferGetHeight(cameraFrame);

    if (self.luminanceTextureRef) {
        CFRelease(self.luminanceTextureRef);
        self.luminanceTextureRef = nil;
    }
    if (self.chrominanceTextureRef) {
        CFRelease(self.chrominanceTextureRef);
        self.chrominanceTextureRef = nil;
    }

    CVOpenGLESTextureCacheFlush([[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache], 0);
    
	CMTime currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);

    [GPUImageContext useImageProcessingContext];
    
    if (CVPixelBufferGetPlaneCount(cameraFrame) > 0) { // Check for YUV planar inputs to do RGB conversion
        if ((self.imageBufferWidth != bufferWidth) && (self.imageBufferHeight != bufferHeight)) {
            self.imageBufferWidth = bufferWidth;
            self.imageBufferHeight = bufferHeight;
        }

        CVReturn err;
        // Y-plane
        glActiveTexture(GL_TEXTURE4);
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache], cameraFrame, NULL, GL_TEXTURE_2D, GL_LUMINANCE, bufferWidth, bufferHeight, GL_LUMINANCE, GL_UNSIGNED_BYTE, 0, &_luminanceTextureRef);

        if (err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        
        self.luminanceTexture = CVOpenGLESTextureGetName(self.luminanceTextureRef);
        glBindTexture(GL_TEXTURE_2D, self.luminanceTexture);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        // UV-plane
        glActiveTexture(GL_TEXTURE5);
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache], cameraFrame, NULL, GL_TEXTURE_2D, GL_LUMINANCE_ALPHA, bufferWidth/2, bufferHeight/2, GL_LUMINANCE_ALPHA, GL_UNSIGNED_BYTE, 1, &_chrominanceTextureRef);
    
        if (err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        
        self.chrominanceTexture = CVOpenGLESTextureGetName(self.chrominanceTextureRef);
        glBindTexture(GL_TEXTURE_2D, self.chrominanceTexture);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

        if (!self.textureRenderDisabled) {
            runSynchronouslyOnVideoProcessingQueue(^{
                [self convertYUVToRGBOutput];

                int rotatedImageBufferWidth = bufferWidth, rotatedImageBufferHeight = bufferHeight;

                if (GPUImageRotationSwapsWidthAndHeight(self.internalRotation)) {
                    rotatedImageBufferWidth = bufferHeight;
                    rotatedImageBufferHeight = bufferWidth;
                }

                [self updateTargetsForVideoCameraUsingCacheTextureAtWidth:rotatedImageBufferWidth height:rotatedImageBufferHeight time:currentTime];
            });

        }
    }
}

typedef struct {
    GLfloat position[2];
    GLfloat texcoord[2];
} Vertex;

const Vertex Vertices[] = {
    { { -1, -1 }, { 0, 0}}, //bottom left
    { {1, -1 }, {1, 0}},  //bottom right
    { {-1, 1 }, {0, 1}}, //top left
    { {1, 1 }, {1, 1}}   //top right
};

const GLushort Indices[] = {
    0, 1, 2,
    2, 1, 3
};

- (void)setupVBOs {
    //create and bind a vao
    glGenVertexArraysOES(1, &vao);
    glBindVertexArrayOES(vao);

    //create and bind a BO for vertex data
    glGenBuffers(1, &vertexBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);

    // copy data into the buffer object
    glBufferData(GL_ARRAY_BUFFER, sizeof(Vertices), Vertices, GL_STATIC_DRAW);

    // set up vertex attributes
    glEnableVertexAttribArray(self.yuvConversionPositionAttribute);
    glVertexAttribPointer(self.yuvConversionPositionAttribute, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*)offsetof(Vertex, position));
    glEnableVertexAttribArray(self.yuvConversionTextureCoordinateAttribute);
    glVertexAttribPointer(self.yuvConversionTextureCoordinateAttribute, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*)offsetof(Vertex, texcoord));


    // Create and bind a BO for index data
    glGenBuffers(1, &indexBuffer);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indexBuffer);

    // copy data into the buffer object
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(Indices), Indices, GL_STATIC_DRAW);

    //unbind it, rebind it only when you needed
    glBindVertexArrayOES(0);
}

- (void)convertYUVToRGBOutput {
    [GPUImageContext setActiveShaderProgram:self.yuvConversionProgram];
    
    int rotatedImageBufferWidth = self.imageBufferWidth, rotatedImageBufferHeight = self.imageBufferHeight;
    
    if (GPUImageRotationSwapsWidthAndHeight(self.internalRotation)) {
        rotatedImageBufferWidth = self.imageBufferHeight;
        rotatedImageBufferHeight = self.imageBufferWidth;
    }

    if (!outputFramebuffer) {
        outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:CGSizeMake(rotatedImageBufferWidth, rotatedImageBufferHeight) textureOptions:self.outputTextureOptions onlyTexture:NO];
    }
    [outputFramebuffer activateFramebuffer];

    if (self.useVbo) {
        glBindVertexArrayOES(vao);

        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        glDrawElements(GL_TRIANGLE_STRIP, sizeof(Indices)/sizeof(GLushort), GL_UNSIGNED_SHORT, 0);

        glBindVertexArrayOES(0);
    } else {
        static const GLfloat squareVertices[] = {
            -1.0f, -1.0f,
            1.0f, -1.0f,
            -1.0f,  1.0f,
            1.0f,  1.0f,
        };

        glActiveTexture(GL_TEXTURE4);
        glBindTexture(GL_TEXTURE_2D, self.luminanceTexture);
        glUniform1i(self.yuvConversionLuminanceTextureUniform, 4);

        glActiveTexture(GL_TEXTURE5);
        glBindTexture(GL_TEXTURE_2D, self.chrominanceTexture);
        glUniform1i(self.yuvConversionChrominanceTextureUniform, 5);

        glUniformMatrix3fv(self.yuvConversionMatrixUniform, 1, GL_FALSE, self.preferredConversion);

        glVertexAttribPointer(self.yuvConversionPositionAttribute, 2, GL_FLOAT, 0, 0, squareVertices);
        glVertexAttribPointer(self.yuvConversionTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, [GPUImageFilter textureCoordinatesForRotation:self.internalRotation]);
        
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    }
}

#pragma mark Orientation

- (void)updateOrientationSendToTargets {
    runSynchronouslyOnVideoProcessingQueue(^{
        
        //    From the iOS 5.0 release notes:
        //    In previous iOS versions, the front-facing camera would always deliver buffers in AVCaptureVideoOrientationLandscapeLeft and the back-facing camera would always deliver buffers in AVCaptureVideoOrientationLandscapeRight.
        
        if ([GPUImageContext supportsFastTextureUpload]) {
            self.outputRotation = kGPUImageNoRotation;
            if ([self cameraPosition] == AVCaptureDevicePositionBack) {
                if (self.horizontallyMirrorRearFacingCamera) {
                    switch(self.outputImageOrientation) {
                        case UIInterfaceOrientationPortrait:self.internalRotation = kGPUImageRotateRightFlipVertical; break;
                        case UIInterfaceOrientationPortraitUpsideDown:self.internalRotation = kGPUImageRotate180; break;
                        case UIInterfaceOrientationLandscapeLeft:self.internalRotation = kGPUImageFlipHorizonal; break;
                        case UIInterfaceOrientationLandscapeRight:self.internalRotation = kGPUImageFlipVertical; break;
                        default:self.internalRotation = kGPUImageNoRotation;
                    }
                }
                else {
                    switch(self.outputImageOrientation) {
                        case UIInterfaceOrientationPortrait:self.internalRotation = kGPUImageRotateRight; break;
                        case UIInterfaceOrientationPortraitUpsideDown:self.internalRotation = kGPUImageRotateLeft; break;
                        case UIInterfaceOrientationLandscapeLeft:self.internalRotation = kGPUImageRotate180; break;
                        case UIInterfaceOrientationLandscapeRight:self.internalRotation = kGPUImageNoRotation; break;
                        default:self.internalRotation = kGPUImageNoRotation;
                    }
                }
            } else {
                if (self.horizontallyMirrorFrontFacingCamera) {
                    switch(self.outputImageOrientation) {
                        case UIInterfaceOrientationPortrait:self.internalRotation = kGPUImageRotateRightFlipVertical; break;
                        case UIInterfaceOrientationPortraitUpsideDown:self.internalRotation = kGPUImageRotateRightFlipHorizontal; break;
                        case UIInterfaceOrientationLandscapeLeft:self.internalRotation = kGPUImageFlipHorizonal; break;
                        case UIInterfaceOrientationLandscapeRight:self.internalRotation = kGPUImageFlipVertical; break;
                        default:self.internalRotation = kGPUImageNoRotation;
                    }
                } else {
                    switch(self.outputImageOrientation) {
                        case UIInterfaceOrientationPortrait:self.internalRotation = kGPUImageRotateRight; break;
                        case UIInterfaceOrientationPortraitUpsideDown:self.internalRotation = kGPUImageRotateLeft; break;
                        case UIInterfaceOrientationLandscapeLeft:self.internalRotation = kGPUImageNoRotation; break;
                        case UIInterfaceOrientationLandscapeRight:self.internalRotation = kGPUImageRotate180; break;
                        default:self.internalRotation = kGPUImageNoRotation;
                    }
                }
            }
        } else {
            if ([self cameraPosition] == AVCaptureDevicePositionBack) {
                if (self.horizontallyMirrorRearFacingCamera) {
                    switch(self.outputImageOrientation) {
                        case UIInterfaceOrientationPortrait:self.outputRotation = kGPUImageRotateRightFlipVertical; break;
                        case UIInterfaceOrientationPortraitUpsideDown:self.outputRotation = kGPUImageRotate180; break;
                        case UIInterfaceOrientationLandscapeLeft:self.outputRotation = kGPUImageFlipHorizonal; break;
                        case UIInterfaceOrientationLandscapeRight:self.outputRotation = kGPUImageFlipVertical; break;
                        default:self.outputRotation = kGPUImageNoRotation;
                    }
                } else {
                    switch(self.outputImageOrientation){
                        case UIInterfaceOrientationPortrait:self.outputRotation = kGPUImageRotateRight; break;
                        case UIInterfaceOrientationPortraitUpsideDown:self.outputRotation = kGPUImageRotateLeft; break;
                        case UIInterfaceOrientationLandscapeLeft:self.outputRotation = kGPUImageRotate180; break;
                        case UIInterfaceOrientationLandscapeRight:self.outputRotation = kGPUImageNoRotation; break;
                        default:self.outputRotation = kGPUImageNoRotation;
                    }
                }
            } else {
                if (self.horizontallyMirrorFrontFacingCamera) {
                    switch(self.outputImageOrientation) {
                        case UIInterfaceOrientationPortrait:self.outputRotation = kGPUImageRotateRightFlipVertical; break;
                        case UIInterfaceOrientationPortraitUpsideDown:self.outputRotation = kGPUImageRotateRightFlipHorizontal; break;
                        case UIInterfaceOrientationLandscapeLeft:self.outputRotation = kGPUImageFlipHorizonal; break;
                        case UIInterfaceOrientationLandscapeRight:self.outputRotation = kGPUImageFlipVertical; break;
                        default:self.outputRotation = kGPUImageNoRotation;
                    }
                } else {
                    switch(self.outputImageOrientation) {
                        case UIInterfaceOrientationPortrait:self.outputRotation = kGPUImageRotateRight; break;
                        case UIInterfaceOrientationPortraitUpsideDown:self.outputRotation = kGPUImageRotateLeft; break;
                        case UIInterfaceOrientationLandscapeLeft:self.outputRotation = kGPUImageNoRotation; break;
                        case UIInterfaceOrientationLandscapeRight:self.outputRotation = kGPUImageRotate180; break;
                        default:self.outputRotation = kGPUImageNoRotation;
                    }
                }
            }
        }
        
        for (id<GPUImageInput> currentTarget in self.targets) {
            NSInteger indexOfObject = [self.targets indexOfObject:currentTarget];
            [currentTarget setInputRotation:self.outputRotation atIndex:[[self->targetTextureIndices objectAtIndex:indexOfObject] integerValue]];
        }
    });
}

- (void)setCameraPosition:(AVCaptureDevicePosition)cameraPosition {
    _cameraPosition = cameraPosition;
    [self updateOrientationSendToTargets];
}

- (void)setOutputImageOrientation:(UIInterfaceOrientation)newValue {
    _outputImageOrientation = newValue;
    [self updateOrientationSendToTargets];
}

- (void)setHorizontallyMirrorFrontFacingCamera:(BOOL)newValue {
    _horizontallyMirrorFrontFacingCamera = newValue;
    [self updateOrientationSendToTargets];
}

- (void)setHorizontallyMirrorRearFacingCamera:(BOOL)newValue {
    _horizontallyMirrorRearFacingCamera = newValue;
    [self updateOrientationSendToTargets];
}

- (void)setDropAllFrames:(BOOL)dropAllFrames {
    _dropAllFrames = dropAllFrames;

    runSynchronouslyOnVideoProcessingQueue(^{});
}

@end
