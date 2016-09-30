#import "HBGPUImageUIElement.h"

@interface HBGPUImageUIElement ()
{
    UIView *view;
    CALayer *layer;
    
    CGSize previousLayerSizeInPixels;
    CMTime time;
    NSTimeInterval actualTimeOfLastUpdate;
}

@end

@implementation HBGPUImageUIElement

#pragma mark -
#pragma mark Initialization and teardown

- (id)initWithView:(UIView *)inputView
{
    if (!(self = [super init]))
    {
		return nil;
    }
    
    view = inputView;
    layer = inputView.layer;
    
    previousLayerSizeInPixels = CGSizeZero;
    [self update];
    
    return self;
}

- (id)initWithLayer:(CALayer *)inputLayer
{
    if (!(self = [super init]))
    {
		return nil;
    }
    
    view = nil;
    layer = inputLayer;
    
    previousLayerSizeInPixels = CGSizeZero;
    [self update];
    
    return self;
}

#pragma mark -
#pragma mark Layer management

- (CGSize)layerSizeInPixels
{
    CGSize pointSize = layer.bounds.size;
    return CGSizeMake(layer.contentsScale * pointSize.width, layer.contentsScale * pointSize.height);
}

- (void)update
{
    [self updateWithTimestamp:kCMTimeIndefinite];
}

- (void)updateUsingCurrentTime
{
    if(CMTIME_IS_INVALID(time)) {
        time = CMTimeMakeWithSeconds(0, 600);
        actualTimeOfLastUpdate = [NSDate timeIntervalSinceReferenceDate];
    } else {
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval diff = now - actualTimeOfLastUpdate;
        time = CMTimeAdd(time, CMTimeMakeWithSeconds(diff, 600));
        actualTimeOfLastUpdate = now;
    }
    
    [self updateWithTimestamp:time];
}

- (void)updateWithTimestamp:(CMTime)frameTime
{
    [GPUImageContext useImageProcessingContext];
    
    CGSize layerPixelSize = [self layerSizeInPixels];
    
    GLubyte *imageData = (GLubyte *) calloc(1, (int)layerPixelSize.width * (int)layerPixelSize.height * 4);
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
        CGColorSpaceRef genericRGBColorspace = CGColorSpaceCreateDeviceRGB();
        CGContextRef imageContext = CGBitmapContextCreate(imageData, (int)layerPixelSize.width, (int)layerPixelSize.height, 8, (int)layerPixelSize.width * 4, genericRGBColorspace,  kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
        CGContextTranslateCTM(imageContext, 0.0f, layerPixelSize.height);
        CGContextScaleCTM(imageContext, self->layer.contentsScale, -self->layer.contentsScale);
        
        [self->layer.modelLayer renderInContext:imageContext];
        
        CGContextRelease(imageContext);
        CGColorSpaceRelease(genericRGBColorspace);
    
        runAsynchronouslyOnVideoProcessingQueue(^{
        
            // TODO: This may not work
            self->outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:layerPixelSize textureOptions:self.outputTextureOptions onlyTexture:YES];
            
            glBindTexture(GL_TEXTURE_2D, [self->outputFramebuffer texture]);
            // no need to use self.outputTextureOptions here, we always need these texture options
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (int)layerPixelSize.width, (int)layerPixelSize.height, 0, GL_BGRA, GL_UNSIGNED_BYTE, imageData);
            
            free(imageData);
            
            for (id<GPUImageInput> currentTarget in self->targets)
            {
                if (currentTarget != self.targetToIgnoreForUpdates)
                {
                    NSInteger indexOfObject = [self->targets indexOfObject:currentTarget];
                    NSInteger textureIndexOfTarget = [[self->targetTextureIndices objectAtIndex:indexOfObject] integerValue];
                    
                    [currentTarget setInputSize:layerPixelSize atIndex:textureIndexOfTarget];
                    [currentTarget newFrameReadyAtTime:frameTime atIndex:textureIndexOfTarget];
                }
            }
        });
    }];
}

@end
