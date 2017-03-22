#import "SimpleVideoFileFilterViewController.h"
#import "GPUImageBeautifyFilter.h"

@implementation SimpleVideoFileFilterViewController
{
#define FLTS_CNT 1
    GPUImageOutput<GPUImageInput> * flts[FLTS_CNT];
    float intensity;
}
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
    }
    return self;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
  
    //NSURL *sampleURL = [[NSBundle mainBundle] URLForResource:@"sample_iPod" withExtension:@"m4v"];
    //NSURL *sampleURL = [[NSBundle mainBundle] URLForResource:@"sample_Clock" withExtension:@"mp4"];
    NSURL *sampleURL = [[NSBundle mainBundle] URLForResource:@"skin_beautification_test_640" withExtension:@"mp4"];
    
    movieFile = [[GPUImageMovie alloc] initWithURL:sampleURL];
    movieFile.runBenchmark = YES;
    movieFile.playAtActualSpeed = NO;
//    filter = [[GPUImageBilateralFilter alloc] init];
//    filter = [[GPUImagePixellateFilter alloc] init];
//    filter = [[GPUImageUnsharpMaskFilter alloc] init];

//    [movieFile addTarget:filter];
    
    intensity = 0.20;
    //flts[0] = [[GPUImageBilateralFilter alloc] init];
    flts[0] = [[GPUImageBeautifyFilter alloc] init];
//    [(GPUImageSingleComponentGaussianBlurFilter *)flts[0] setBlurRadiusInPixels:2];
//    [(GPUImageSingleComponentGaussianBlurFilter *)flts[0] setTexelSpacingMultiplier: 1.0];
    for(int i=0; i<FLTS_CNT; i++) {
        [(GPUImageBeautifyFilter *)flts[i] setDistanceNormalizationFactor:4.0];
        [(GPUImageBeautifyFilter *)flts[i] setIntensity:intensity];
    }
    
    [movieFile addTarget:flts[0]];
    
    for(int i=1;i<FLTS_CNT;i++) {
        //flts[i] = [[GPUImagePixellateFilter alloc] init];
        flts[i] = [[GPUImageBeautifyFilter alloc] init];
        [flts[i-1] addTarget:flts[i]];
    }

    // Only rotate the video for display, leave orientation the same for recording
    GPUImageView *filterView = (GPUImageView *)self.view;
    //[filter addTarget:filterView];
    [flts[FLTS_CNT-1] addTarget:filterView];

    // In addition to displaying to the screen, write out a processed version of the movie to disk
    NSString *pathToMovie = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Movie.m4v"];
    unlink([pathToMovie UTF8String]); // If a file already exists, AVAssetWriter won't let you record new frames, so delete the old movie
    NSURL *movieURL = [NSURL fileURLWithPath:pathToMovie];

    //movieWriter = [[GPUImageMovieWriter alloc] initWithMovieURL:movieURL size:CGSizeMake(640.0, 480.0)];
    //[filter addTarget:movieWriter];

    // Configure this for video from the movie file, where we want to preserve all video frames and audio samples
    //movieWriter.shouldPassthroughAudio = YES;
    //movieFile.audioEncodingTarget = movieWriter;
    //[movieFile enableSynchronizedEncodingUsingMovieWriter:movieWriter];
    
    //[movieWriter startRecording];
    [movieFile startProcessing];
    NSLog(@"playback started");
    
    timer = [NSTimer scheduledTimerWithTimeInterval:1.0f
                                             target:self
                                           selector:@selector(retrievingProgress)
                                           userInfo:nil
                                            repeats:YES];
    
//    [movieWriter setCompletionBlock:^{
//        [filter removeTarget:movieWriter];
//        [movieWriter finishRecording];
//        
//        dispatch_async(dispatch_get_main_queue(), ^{
//            [timer invalidate];
//            self.progressLabel.text = @"100%";
//        });
//    }];
    
}

- (void)retrievingProgress
{
    self.progressLabel.text = [NSString stringWithFormat:@"%d%%", (int)(movieFile.progress * 100)];
    NSLog(@"playback progress %f",movieFile.progress);
    if(movieFile.progress >= 1.0) {
        [timer invalidate];
    }
}

- (void)viewDidUnload
{
    [self setProgressLabel:nil];
    [self setIntensityLabel:nil];
    [super viewDidUnload];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (IBAction)updatePixelWidth:(id)sender
{
    intensity = [(UISlider *)sender value]*5;
//    [(GPUImageUnsharpMaskFilter *)filter setIntensity:[(UISlider *)sender value]];
//    [(GPUImagePixellateFilter *)filter setFractionalWidthOfAPixel:[(UISlider *)sender value]];
//    [(GPUImageBilateralFilter *)filter setDistanceNormalizationFactor:[(UISlider *)sender value]*40];
//    [(GPUImageBilateralFilter *)flts[FLTS_CNT-1] setDistanceNormalizationFactor:[(UISlider *)sender value]*40];
   // [(GPUImageSingleComponentGaussianBlurFilter *)flts[FLTS_CNT-1] setBlurRadiusInPixels:[(UISlider *)sender value]*40];
    for(int i=0; i<FLTS_CNT; i++) {
        //[(GPUImageBeautifyFilter *)flts[i] setDistanceNormalizationFactor:[(UISlider *)sender value]*40];
        [(GPUImageBeautifyFilter *)flts[i] setIntensity:intensity];
    }
    self.intensityLabel.text = [NSString stringWithFormat:@"intensity: %.1f",intensity];
}

- (void)dealloc {
    [_progressLabel release];
    [_intensityLabel release];
    [super dealloc];
}
@end
