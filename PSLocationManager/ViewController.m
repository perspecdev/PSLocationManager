//
//  ViewController.m
//  PSLocationManager
//
//  Created by Daniel Isenhower on 2/22/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

@synthesize strengthLabel = _strengthLabel;
@synthesize distanceLabel = _distanceLabel;

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    [PSLocationManager sharedLocationManager].delegate = self;
    [[PSLocationManager sharedLocationManager] prepLocationUpdates];
    [[PSLocationManager sharedLocationManager] startLocationUpdates];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
    } else {
        return YES;
    }
}

#pragma mark PSLocationManagerDelegate

- (void)locationManager:(PSLocationManager *)locationManager signalStrengthChanged:(PSLocationManagerGPSSignalStrength)signalStrength {
    NSString *strengthText;
    if (signalStrength == PSLocationManagerGPSSignalStrengthWeak) {
        strengthText = NSLocalizedString(@"Weak", @"");
    } else if (signalStrength == PSLocationManagerGPSSignalStrengthStrong) {
        strengthText = NSLocalizedString(@"Strong", @"");
    } else {
        strengthText = NSLocalizedString(@"...", @"");
    }
    
    self.strengthLabel.text = strengthText;
}

- (void)locationManagerSignalConsistentlyWeak:(PSLocationManager *)locationManager {
    self.strengthLabel.text = NSLocalizedString(@"Consistently Weak", @"");
}

- (void)locationManager:(PSLocationManager *)locationManager distanceUpdated:(CLLocationDistance)distance {
    self.distanceLabel.text = [NSString stringWithFormat:@"%.2f %@", distance, NSLocalizedString(@"meters", @"")];
}

- (void)locationManager:(PSLocationManager *)locationManager error:(NSError *)error {
    // location services is probably not enabled for the app
    self.strengthLabel.text = NSLocalizedString(@"Unable to determine location", @"");
}

@end
