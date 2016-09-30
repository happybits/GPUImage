//
//  HBGPUImageCropFilter.m
//  Marco Polo
//
//  Created by Dave Walker on 2/13/15.
//  Copyright (c) 2015 Happy Bits. All rights reserved.
//

#import "HBGPUImageCropFilter.h"

@interface HBGPUImageCropFilter()

@property (nonatomic, assign) CGSize dimensions;
@property (nonatomic, assign) CGSize lastSize;
@end

@implementation HBGPUImageCropFilter

- (id)initWithTargetDimensions:(CGSize)dimensions {
    if (self = [super init]) {
        _dimensions = dimensions;
        _lastSize = CGSizeMake(0, 0);
    }
    
    return self;
}

- (void)setInputSize:(CGSize)newSize atIndex:(NSInteger)textureIndex {
    if (self.lastSize.width != newSize.width || self.lastSize.height != newSize.height) {
        self.lastSize = newSize;
        
        if (newSize.height == 0) {
            [self setCropRegion:CGRectMake(0, 0, 1.0, 1.0)];
        } else {
            CGFloat sizeRatio = newSize.width / newSize.height;
            CGFloat dimRatio = self.dimensions.width / self.dimensions.height;
            
            CGFloat w, h;
            if (dimRatio > sizeRatio) {
                w = 1;
                h = sizeRatio / dimRatio;
            } else {
                h = 1;
                w = dimRatio / sizeRatio;
            }
            
            // Crop from the center
            CGFloat offsetW = (1.0f - w) / 2;
            CGFloat offsetH = (1.0f - h) / 2;
            
            [self setCropRegion:CGRectMake(offsetW, offsetH, w, h)];
        }
    }
    
    [super setInputSize:newSize atIndex:textureIndex];
}

@end
