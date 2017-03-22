//
//  ViewController.m
//  MPGPU
//
//  Created by Dave Walker on 3/18/17.
//  Copyright © 2017 Joya Communications. All rights reserved.
//

#import "ViewController.h"
#import "GPUImage.h"
#import "FilterConfiguration.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet GPUImageView *preview;
@property (weak, nonatomic) IBOutlet UILabel *titleLabel;
@property (weak, nonatomic) IBOutlet UILabel *usageLabel;
@property (weak, nonatomic) IBOutlet UILabel *intensityLabel;
@property (weak, nonatomic) IBOutlet UISlider *controlSlider;

@property (nonatomic, strong) FilterConfiguration *config;
@property (nonatomic, strong) NSTimer *runTimer;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    _config = [FilterConfiguration new];
    _config.preview = _preview;

    _config.includeCameraRender = YES;
    _config.includePreview = YES;
    _config.includeBeautify = YES;
    [_config startCamera];

    _titleLabel.text = _config.configName;

    [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(updateUsage) userInfo:nil repeats:YES];

    [self onReset:nil];
    [self controlSliderValueChanged:self.controlSlider];
}

- (void)updateUsage {
    self.usageLabel.text = [NSString stringWithFormat:@"CPU: %.1f%%", self.config.cpuUsage];
}

- (IBAction)controlSliderValueChanged:(UISlider *)sender {
    NSLog(@"slider value = %f", sender.value);
    self.intensityLabel.text = [NSString stringWithFormat:@"%.2f", sender.value];
    self.config.intensity = sender.value;
}

- (IBAction)onReset:(id)sender {
    _usageLabel.text = @"";
    [self.runTimer invalidate];
    [self.config resetStats];

    self.runTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(showCpuUsageAlertView) userInfo:nil repeats:NO];
}

- (void)showCpuUsageAlertView {
    FrameCounters counters = self.config.counters;
    float cpu = self.config.cpuUsage;
    float milliseconds = counters.processingTime * 1000;
    UIAlertView *alertView = [[UIAlertView alloc]
                              initWithTitle:@"30s summary"
                              message:[NSString stringWithFormat:@"count=%@ cpu=%.1f%% time=%.1fms", @(counters.count), cpu, milliseconds]
                              delegate:nil
                              cancelButtonTitle:@"OK"
                              otherButtonTitles:nil];
    [alertView show];
}

@end
