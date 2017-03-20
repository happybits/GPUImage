//
//  HBAutoExposureAdjustment.m
//  Marco Polo
//
//  Created by Dave Walker on 12/13/16.
//  Copyright © 2016 Happy Bits. All rights reserved.
//

#import "AutoExposureAdjustment.h"

NSString *const kHBLuminosityFirstStageVertexShaderString = SHADER_STRING
(
 attribute vec4 position;
 attribute vec4 inputTextureCoordinate;

 uniform float texelWidth;
 uniform float texelHeight;

 varying vec2 upperLeftInputTextureCoordinate;
 varying vec2 upperRightInputTextureCoordinate;
 varying vec2 lowerLeftInputTextureCoordinate;
 varying vec2 lowerRightInputTextureCoordinate;

 void main()
 {
     gl_Position = position;

     vec2 middleTextureCoordinate = inputTextureCoordinate.xy * vec2(0.75, 0.75) + vec2(0.125, 0.125);
     upperLeftInputTextureCoordinate = middleTextureCoordinate.xy + vec2(-texelWidth, -texelHeight);
     upperRightInputTextureCoordinate = middleTextureCoordinate.xy + vec2(texelWidth, -texelHeight);
     lowerLeftInputTextureCoordinate = middleTextureCoordinate.xy + vec2(-texelWidth, texelHeight);
     lowerRightInputTextureCoordinate = middleTextureCoordinate.xy + vec2(texelWidth, texelHeight);
 }
 );

NSString *const kHBLuminosityVertexShaderString = SHADER_STRING
(
 attribute vec4 position;
 attribute vec4 inputTextureCoordinate;

 uniform float texelWidth;
 uniform float texelHeight;

 varying vec2 upperLeftInputTextureCoordinate;
 varying vec2 upperRightInputTextureCoordinate;
 varying vec2 lowerLeftInputTextureCoordinate;
 varying vec2 lowerRightInputTextureCoordinate;

 void main()
 {
     gl_Position = position;

     upperLeftInputTextureCoordinate = inputTextureCoordinate.xy + vec2(-texelWidth, -texelHeight);
     upperRightInputTextureCoordinate = inputTextureCoordinate.xy + vec2(texelWidth, -texelHeight);
     lowerLeftInputTextureCoordinate = inputTextureCoordinate.xy + vec2(-texelWidth, texelHeight);
     lowerRightInputTextureCoordinate = inputTextureCoordinate.xy + vec2(texelWidth, texelHeight);
 }
 );

NSString *const kHBLuminosityFragmentShaderString = SHADER_STRING
(
 precision highp float;

 uniform sampler2D inputImageTexture;

 varying highp vec2 outputTextureCoordinate;

 varying highp vec2 upperLeftInputTextureCoordinate;
 varying highp vec2 upperRightInputTextureCoordinate;
 varying highp vec2 lowerLeftInputTextureCoordinate;
 varying highp vec2 lowerRightInputTextureCoordinate;

 const highp vec3 W = vec3(0.2125, 0.7154, 0.0721);

 void main()
 {
     highp float upperLeftLuminance = dot(texture2D(inputImageTexture, upperLeftInputTextureCoordinate).rgb, W);
     highp float upperRightLuminance = dot(texture2D(inputImageTexture, upperRightInputTextureCoordinate).rgb, W);
     highp float lowerLeftLuminance = dot(texture2D(inputImageTexture, lowerLeftInputTextureCoordinate).rgb, W);
     highp float lowerRightLuminance = dot(texture2D(inputImageTexture, lowerRightInputTextureCoordinate).rgb, W);

     highp float luminosity = 0.25 * (upperLeftLuminance + upperRightLuminance + lowerLeftLuminance + lowerRightLuminance);
     gl_FragColor = vec4(luminosity, luminosity, luminosity, 1.0);
 }
 );

const NSUInteger DECIMATION_FRAMES = 8;

@interface AutoExposureAdjustment()

@property (nonatomic, strong) GPUImageExposureFilter *exposureFilter;
@property (nonatomic, assign) CGFloat exposure;
@property (nonatomic, assign) CGFloat previousLuminosity;
@property (nonatomic, assign) CGFloat currentLuminosity;
@property (nonatomic, assign) CGFloat frameAdjustment;
@property (nonatomic, assign) NSUInteger decimationCount;

@property (nonatomic, assign) NSUInteger numberOfStages;
@property (nonatomic, assign) GLubyte *rawImagePixels;
@property (nonatomic, assign) CGSize finalStageSize;
@property (nonatomic, assign) CGSize inputSize;

@property (nonatomic, strong) NSMutableArray *luminanceStages;

@end

@implementation AutoExposureAdjustment

#pragma mark -
#pragma mark Initialization and teardown

- (instancetype)initWithExposureFilter:(GPUImageExposureFilter *)exposureFilter {

    if (!(self = [super initWithVertexShaderFromString:kHBLuminosityFirstStageVertexShaderString
                              fragmentShaderFromString:kHBLuminosityFragmentShaderString])) {
        return nil;
    }

    _exposureFilter = exposureFilter;

    return self;
}

- (void)dealloc {
    if (self.rawImagePixels != NULL) {
        free(self.rawImagePixels);
    }
}

- (void)setInputSize:(CGSize)newSize atIndex:(NSInteger)textureIndex {
    if (CGSizeEqualToSize(newSize, self.inputSize)) {
        return;
    }

    // In a series of stages, we will render the average luminance value of 4 pixels into a frame buffer
    // 1/4 of the size, until the average of the entire frame is in a very small number of pixels.
    NSUInteger numberOfReductionsInX = (NSUInteger)floor(log(newSize.width) / log(4.0f));
    NSUInteger numberOfReductionsInY = (NSUInteger)floor(log(newSize.height) / log(4.0f));
    NSUInteger reductionsToHitSideLimit = MIN(numberOfReductionsInX, numberOfReductionsInY);

    // The first reduction is done by this filter itself. Create an array of new filters for further
    // reductions
    LuminanceStageFilter *filter = self;
    self.luminanceStages = [NSMutableArray new];
    for (NSUInteger currentReduction = 0; currentReduction < reductionsToHitSideLimit; currentReduction++) {
        CGSize currentStageSize = CGSizeMake(floor(newSize.width / pow(4.0f, currentReduction + 1.0f)),
                                             floor(newSize.height / pow(4.0f, currentReduction + 1.0f)));

        filter.outputSize = currentStageSize;
        self.finalStageSize = currentStageSize;

        if (currentReduction < (reductionsToHitSideLimit - 1)) {
            filter = [[LuminanceStageFilter alloc] initWithVertexShaderFromString:kHBLuminosityVertexShaderString
                                                           fragmentShaderFromString:kHBLuminosityFragmentShaderString];

            [filter setInputSize:currentStageSize atIndex:0];
            [self.luminanceStages addObject:filter];
        }
    }
}

- (void)renderToTextureWithVertices:(const GLfloat *)vertices textureCoordinates:(const GLfloat *)textureCoordinates {
    if (self.preventRendering) {
        [firstInputFramebuffer unlock];
        return;
    }

    // Only recalculate luminance every few frames for performance reasons.
    if (self.decimationCount++ % DECIMATION_FRAMES == 0) {

        // Generate the average luminosity in a series of stages.
        GLuint currentTexture = [firstInputFramebuffer texture];
        GPUImageFramebuffer *framebuffer = [self renderReducedLuminanceFromTexture:currentTexture vertices:vertices textureCoordinates:textureCoordinates];

        for (LuminanceStageFilter *filter in self.luminanceStages) {
            currentTexture = [framebuffer texture];
            [framebuffer unlock];
            framebuffer = [filter renderReducedLuminanceFromTexture:currentTexture vertices:vertices textureCoordinates:textureCoordinates];
        }

        // Extract a single average luminosity number from the final stage.
        CGFloat luminosity = [self extractLuminosityFromFramebuffer:framebuffer];

        [framebuffer unlock];

        // On the first frame, use luminance value directly. Afterwards, accumulate changes
        // for a smoother transition.
        if (self.currentLuminosity == 0) {
            self.currentLuminosity = luminosity;
            self.previousLuminosity = luminosity;
        } else {
            self.previousLuminosity = self.currentLuminosity;
            float alpha = 0.35f;
            self.currentLuminosity = self.currentLuminosity * (1.f - alpha) + luminosity * alpha;
        }

        self.frameAdjustment = (self.currentLuminosity - self.previousLuminosity) / DECIMATION_FRAMES;
    }

    [self removeOutputFramebuffer];
    [firstInputFramebuffer unlock];

    // Use a smoothed value between the most recent luminance calculation and the one before that as input
    // to the exposure calculation.
    self.previousLuminosity += self.frameAdjustment;
    CGFloat exposureLuminosity = self.previousLuminosity;

    // For luminosity values below .2, apply a linear increase to exposure.
    CGFloat newExposure;
    if (exposureLuminosity < .2f) {
        newExposure = 3.f - (exposureLuminosity * 15);
    } else {
        newExposure = 0;
    }
    if (newExposure != self.exposure) {
        self.exposure = newExposure;
        self.exposureFilter.exposure = newExposure;
    }
}

- (CGFloat)extractLuminosityFromFramebuffer:(GPUImageFramebuffer *)framebuffer {

    // we need a normal color texture for this filter
    NSAssert(self.outputTextureOptions.internalFormat == GL_RGBA, @"The output texture format for this filter must be GL_RGBA.");
    NSAssert(self.outputTextureOptions.type == GL_UNSIGNED_BYTE, @"The type of the output texture of this filter must be GL_UNSIGNED_BYTE.");

    NSUInteger totalNumberOfPixels = (NSUInteger)round(self.finalStageSize.width * self.finalStageSize.height);
    if (self.rawImagePixels == NULL) {
        self.rawImagePixels = (GLubyte *)malloc(totalNumberOfPixels * 4);
    }

    [GPUImageContext useImageProcessingContext];
    [framebuffer activateFramebuffer];

    glReadPixels(0, 0, (int)self.finalStageSize.width, (int)self.finalStageSize.height, GL_RGBA, GL_UNSIGNED_BYTE, self.rawImagePixels);

    NSUInteger luminanceTotal = 0;
    NSUInteger byteIndex = 0;
    for (NSUInteger currentPixel = 0; currentPixel < totalNumberOfPixels; currentPixel++) {
        luminanceTotal += self.rawImagePixels[byteIndex];
        byteIndex += 4;
    }

    return (CGFloat)luminanceTotal / (CGFloat)totalNumberOfPixels / 255.0f;
}

- (void)setInputRotation:(GPUImageRotationMode)newInputRotation atIndex:(NSInteger)textureIndex {
    inputRotation = kGPUImageNoRotation;
}


@end

@interface LuminanceStageFilter()

@property (nonatomic, assign) GLint texelWidthUniform;
@property (nonatomic, assign) GLint texelHeightUniform;

@end

@implementation LuminanceStageFilter

- (instancetype)initWithVertexShaderFromString:(NSString *)vertexShaderString fragmentShaderFromString:(NSString *)fragmentShaderString {
    if (self = [super initWithVertexShaderFromString:vertexShaderString fragmentShaderFromString:fragmentShaderString]) {

        _texelWidthUniform = [filterProgram uniformIndex:@"texelWidth"];
        _texelHeightUniform = [filterProgram uniformIndex:@"texelHeight"];
    }

    return self;
}

- (GPUImageFramebuffer *)renderReducedLuminanceFromTexture:(GLuint)inputTexture vertices:(const GLfloat *)vertices textureCoordinates:(const GLfloat *)textureCoordinates {

    [GPUImageContext setActiveShaderProgram:filterProgram];

    glVertexAttribPointer(filterPositionAttribute, 2, GL_FLOAT, 0, 0, vertices);
    glVertexAttribPointer(filterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, textureCoordinates);

    outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:self.outputSize textureOptions:self.outputTextureOptions onlyTexture:NO];
    [outputFramebuffer activateFramebuffer];

    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    glActiveTexture(GL_TEXTURE2);
    glBindTexture(GL_TEXTURE_2D, inputTexture);

    glUniform1i(filterInputTextureUniform, 2);

    glUniform1f(self.texelWidthUniform, (float)(0.25f / self.outputSize.width));
    glUniform1f(self.texelHeightUniform, (float)(0.25f / self.outputSize.height));

    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

    return outputFramebuffer;
}

@end
