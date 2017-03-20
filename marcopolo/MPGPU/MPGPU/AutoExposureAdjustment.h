//
//  AutoExposureAdjustment.h
//  Marco Polo
//
//  Created by Dave Walker on 12/13/16.
//  Copyright © 2016 Happy Bits. All rights reserved.
//

#import "GPUImage.h"
#import "GPUImageExposureFilter.h"

@interface LuminanceStageFilter : GPUImageFilter

@property (nonatomic, assign) CGSize outputSize;

- (GPUImageFramebuffer *)renderReducedLuminanceFromTexture:(GLuint)inputTexture vertices:(const GLfloat *)vertices textureCoordinates:(const GLfloat *)textureCoordinates;

@end

@interface AutoExposureAdjustment : LuminanceStageFilter

- (instancetype)initWithExposureFilter:(GPUImageExposureFilter *)exposureFilter;

@end
