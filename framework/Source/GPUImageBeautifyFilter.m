//
//  GPUImageBeautifyFilter.m
//  Marco Polo
//
//  Created by Joel Drotleff on 10/7/16.
//  Copyright © 2016 Happy Bits. All rights reserved.
//

#import "GPUImageBilateralFilter.h"
#import "GPUImageCannyEdgeDetectionFilter.h"
#import "GPUImageHSBFilter.h"
#import "GPUImageBeautifyFilter.h"
#import "GPUImageThreeInputFilter.h"

// Internal CombinationFilter(It should not be used outside)
#define USE_CANNY 0

#if USE_CANNY
@interface GPUImageCombinationFilter : GPUImageThreeInputFilter
{
    GLint smoothDegreeUniform;
}

@property (nonatomic, assign) CGFloat intensity;

@end

// N.B. Using GPUImage's SHADER_STRING causes macro replacement, which replaces 'log' with
// something like 'tg_log' which leads to a crash.
#define NSStringMultiline(text) @ #text

NSString *const kGPUImageBeautifyFragmentShaderString = NSStringMultiline (
 varying highp vec2 textureCoordinate;
 varying highp vec2 textureCoordinate2;
 varying highp vec2 textureCoordinate3;
 
 uniform sampler2D inputImageTexture;
 uniform sampler2D inputImageTexture2;
 uniform sampler2D inputImageTexture3;
 uniform mediump float smoothDegree;
 
 void main()
 {
     highp vec4 bilateral = texture2D(inputImageTexture, textureCoordinate);
     highp vec4 canny = texture2D(inputImageTexture2, textureCoordinate2);
     highp vec4 origin = texture2D(inputImageTexture3,textureCoordinate3);
     highp vec4 smooth;
     lowp float r = origin.r;
     lowp float g = origin.g;
     lowp float b = origin.b;
     if (canny.r < 0.2 && r > 0.3725 && g > 0.1568 && b > 0.0784 && r > b && (max(max(r, g), b) - min(min(r, g), b)) > 0.0588 && abs(r-g) > 0.0588) {
         smooth = (1.0 - smoothDegree) * (origin - bilateral) + bilateral;
     }
     else {
         smooth = origin;
     }
     smooth.r = log(1.0 + 0.2 * smooth.r)/log(1.2);
     smooth.g = log(1.0 + 0.2 * smooth.g)/log(1.2);
     smooth.b = log(1.0 + 0.2 * smooth.b)/log(1.2);
     gl_FragColor = smooth;
 }
 );

#else  // CANNY

//NO CANNY

@interface GPUImageCombinationFilter : GPUImageTwoInputFilter // GPUImageThreeInputFilter
{
    GLint smoothDegreeUniform;
}

@property (nonatomic, assign) CGFloat intensity;

@end

// N.B. Using GPUImage's SHADER_STRING causes macro replacement, which replaces 'log' with
// something like 'tg_log' which leads to a crash.
#define NSStringMultiline(text) @ #text

NSString *const kGPUImageBeautifyFragmentShaderString = NSStringMultiline (
    varying highp vec2 textureCoordinate;
    varying highp vec2 textureCoordinate2;
    //varying highp vec2 textureCoordinate3;

    uniform sampler2D inputImageTexture;
    uniform sampler2D inputImageTexture2;
    //uniform sampler2D inputImageTexture3;
    uniform mediump float smoothDegree;

    void main()
    {
       highp vec4 bilateral = texture2D(inputImageTexture, textureCoordinate);
       //highp vec4 canny = texture2D(inputImageTexture2, textureCoordinate2);
       //highp vec4 origin = texture2D(inputImageTexture3,textureCoordinate3);
       highp vec4 origin = texture2D(inputImageTexture2,textureCoordinate2);
       highp vec4 smooth;
       lowp float r = origin.r;
       lowp float g = origin.g;
       lowp float b = origin.b;
       //if (canny.r < 0.2 && r > 0.3725 && g > 0.1568 && b > 0.0784 && r > b && (max(max(r, g), b) - min(min(r, g), b)) > 0.0588 && abs(r-g) > 0.0588) {
       if (r > 0.3725 && g > 0.1568 && b > 0.0784 && r > b && (max(max(r, g), b) - min(min(r, g), b)) > 0.0588 && abs(r-g) > 0.0588) {
           smooth = (1.0 - smoothDegree) * (origin - bilateral) + bilateral;
       }
       else {
           smooth = origin;
       }
       smooth.r = log(1.0 + 0.2 * smooth.r)/log(1.2);
       smooth.g = log(1.0 + 0.2 * smooth.g)/log(1.2);
       smooth.b = log(1.0 + 0.2 * smooth.b)/log(1.2);
       gl_FragColor = smooth;
    }
    );
#endif //CANNY

@implementation GPUImageCombinationFilter

- (id)init {
    if (self = [super initWithFragmentShaderFromString:kGPUImageBeautifyFragmentShaderString]) {
        smoothDegreeUniform = [filterProgram uniformIndex:@"smoothDegree"];
    }
    self.intensity = 0.25F;
    return self;
}

- (void)setIntensity:(CGFloat)intensity {
    _intensity = intensity;
    [self setFloat:(GLfloat)intensity forUniform:smoothDegreeUniform program:filterProgram];
}

@end

@implementation GPUImageBeautifyFilter

@synthesize distanceNormalizationFactor = _distanceNormalizationFactor;
@synthesize intensity = _intensity;

- (void)setDistanceNormalizationFactor:(CGFloat)newValue
{
    bilateralFilter.distanceNormalizationFactor = newValue;
}

- (void)setIntensity:(CGFloat)newValue
{
    combinationFilter.intensity = newValue;
}

- (id)init;
{
    if (!(self = [super init]))
    {
        return nil;
    }
    
    // First pass: face smoothing filter
    bilateralFilter = [[GPUImageBilateralFilter alloc] init];
    bilateralFilter.distanceNormalizationFactor = 4.0;
    [self addFilter:bilateralFilter];
    
#if USE_CANNY
    // Second pass: edge detection
    cannyEdgeFilter = [[GPUImageCannyEdgeDetectionFilter alloc] init];
    [self addFilter:cannyEdgeFilter];
#endif
    
    // Third pass: combination bilateral, edge detection and origin
    combinationFilter = [[GPUImageCombinationFilter alloc] init];
    [self addFilter:combinationFilter];
    
    // Adjust HSB
    hsbFilter = [[GPUImageHSBFilter alloc] init];
    [hsbFilter adjustBrightness:1.0F]; // disabled
    [hsbFilter adjustSaturation:1.1F]; // disabled
    
    [bilateralFilter addTarget:combinationFilter];
#if USE_CANNY
    [cannyEdgeFilter addTarget:combinationFilter];
#endif
    
    [combinationFilter addTarget:hsbFilter];

#if USE_CANNY
    self.initialFilters = [NSArray arrayWithObjects:bilateralFilter,cannyEdgeFilter,combinationFilter,nil];
#else
    self.initialFilters = [NSArray arrayWithObjects:bilateralFilter,/*cannyEdgeFilter,*/combinationFilter,nil];
#endif
    self.terminalFilter = hsbFilter;

    return self;
}

#pragma mark -
#pragma mark GPUImageInput protocol

- (void)newFrameReadyAtTime:(CMTime)frameTime atIndex:(NSInteger)textureIndex;
{
    for (GPUImageOutput<GPUImageInput> *currentFilter in self.initialFilters)
    {
        if (currentFilter != self.inputFilterToIgnoreForUpdates)
        {
            if (currentFilter == combinationFilter) {
                textureIndex = 2;
            }
            [currentFilter newFrameReadyAtTime:frameTime atIndex:textureIndex];
        }
    }
}

- (void)setInputFramebuffer:(GPUImageFramebuffer *)newInputFramebuffer atIndex:(NSInteger)textureIndex;
{
    for (GPUImageOutput<GPUImageInput> *currentFilter in self.initialFilters)
    {
        if (currentFilter == combinationFilter) {
            textureIndex = 2;
        }
        [currentFilter setInputFramebuffer:newInputFramebuffer atIndex:textureIndex];
    }
}

@end
