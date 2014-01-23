//
//  LocationManager.m
//  Faster
//
//  Created by Daniel Isenhower on 1/6/12.
//  daniel@perspecdev.com
//  Copyright (c) 2012 PerspecDev Solutions LLC. All rights reserved.
//
//  For more details, check out the blog post about this here:
//  http://perspecdev.com/blog/2012/02/22/using-corelocation-on-ios-to-track-a-users-distance-and-speed/
//
//  Want to use this code in your app?  Feel free!  I would love it if you would send me a quick email
//  about your project.
//
//
//  
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
//  associated documentation files (the "Software"), to deal in the Software without restriction,
//  including without limitation the rights to use, copy, modify, merge, publish, distribute,
//  sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//  
//  The above copyright notice and this permission notice shall be included in all copies or
//  substantial portions of the Software.
//  
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
//  NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
//  DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

static const NSUInteger kDistanceFilter = 5; // the minimum distance (meters) for which we want to receive location updates (see docs for CLLocationManager.distanceFilter)
static const NSUInteger kHeadingFilter = 30; // the minimum angular change (degrees) for which we want to receive heading updates (see docs for CLLocationManager.headingFilter)
static const NSUInteger kDistanceAndSpeedCalculationInterval = 3; // the interval (seconds) at which we calculate the user's distance and speed
static const NSUInteger kMinimumLocationUpdateInterval = 10; // the interval (seconds) at which we ping for a new location if we haven't received one yet
static const NSUInteger kNumLocationHistoriesToKeep = 5; // the number of locations to store in history so that we can look back at them and determine which is most accurate
static const NSUInteger kValidLocationHistoryDeltaInterval = 3; // the maximum valid age in seconds of a location stored in the location history
static const NSUInteger kNumSpeedHistoriesToAverage = 3; // the number of speeds to store in history so that we can average them to get the current speed
static const NSUInteger kPrioritizeFasterSpeeds = 1; // if > 0, the currentSpeed and complete speed history will automatically be set to to the new speed if the new speed is faster than the averaged speed
static const NSUInteger kMinLocationsNeededToUpdateDistanceAndSpeed = 3; // the number of locations needed in history before we will even update the current distance and speed
static const CGFloat kRequiredHorizontalAccuracy = 20.0; // the required accuracy in meters for a location.  if we receive anything above this number, the delegate will be informed that the signal is weak
static const CGFloat kMaximumAcceptableHorizontalAccuracy = 70.0; // the maximum acceptable accuracy in meters for a location.  anything above this number will be completely ignored
static const NSUInteger kGPSRefinementInterval = 15; // the number of seconds at which we will attempt to achieve kRequiredHorizontalAccuracy before giving up and accepting kMaximumAcceptableHorizontalAccuracy

static const CGFloat kSpeedNotSet = -1.0;

#import "PSLocationManager.h"

@interface PSLocationManager ()

@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) NSTimer *locationPingTimer;
@property (nonatomic) PSLocationManagerGPSSignalStrength signalStrength;
@property (nonatomic, strong) CLLocation *lastRecordedLocation;
@property (nonatomic) CLLocationDistance totalDistance;
@property (nonatomic, strong) NSMutableArray *locationHistory;
@property (nonatomic, strong) NSDate *startTimestamp;
@property (nonatomic) double currentSpeed;
@property (nonatomic, strong) NSMutableArray *speedHistory;
@property (nonatomic) NSUInteger lastDistanceAndSpeedCalculation;
@property (nonatomic) BOOL forceDistanceAndSpeedCalculation;
@property (nonatomic) NSTimeInterval pauseDelta;
@property (nonatomic) NSTimeInterval pauseDeltaStart;
@property (nonatomic) BOOL readyToExposeDistanceAndSpeed;
@property (nonatomic) BOOL checkingSignalStrength;
@property (nonatomic) BOOL allowMaximumAcceptableAccuracy;

- (void)checkSustainedSignalStrength;
- (void)requestNewLocation;

@end


@implementation PSLocationManager

@synthesize delegate = _delegate;

@synthesize locationManager = _locationManager;
@synthesize locationPingTimer = _locationPingTimer;
@synthesize signalStrength = _signalStrength;
@synthesize lastRecordedLocation = _lastRecordedLocation;
@synthesize totalDistance = _totalDistance;
@synthesize locationHistory = _locationHistory;
@synthesize totalSeconds = _totalSeconds;
@synthesize startTimestamp = _startTimestamp;
@synthesize currentSpeed = _currentSpeed;
@synthesize speedHistory = _speedHistory;
@synthesize lastDistanceAndSpeedCalculation = _lastDistanceAndSpeedCalculation;
@synthesize forceDistanceAndSpeedCalculation = _forceDistanceAndSpeedCalculation;
@synthesize pauseDelta = _pauseDelta;
@synthesize pauseDeltaStart = _pauseDeltaStart;
@synthesize readyToExposeDistanceAndSpeed = _readyToExposeDistanceAndSpeed;
@synthesize allowMaximumAcceptableAccuracy = _allowMaximumAcceptableAccuracy;
@synthesize checkingSignalStrength = _checkingSignalStrength;

+ (id)sharedLocationManager {
    static dispatch_once_t pred;
    static PSLocationManager *locationManagerSingleton = nil;
    
    dispatch_once(&pred, ^{
        locationManagerSingleton = [[self alloc] init];
    });
    return locationManagerSingleton;
}

- (id)init {
    if ((self = [super init])) {
        if ([CLLocationManager locationServicesEnabled]) {
            self.locationManager = [[CLLocationManager alloc] init];
            self.locationManager.delegate = self;
            self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
            self.locationManager.distanceFilter = kDistanceFilter;
            self.locationManager.headingFilter = kHeadingFilter;
        }
        
        self.locationHistory = [NSMutableArray arrayWithCapacity:kNumLocationHistoriesToKeep];
        self.speedHistory = [NSMutableArray arrayWithCapacity:kNumSpeedHistoriesToAverage];
        [self resetLocationUpdates];
    }
    
    return self;
}

- (void)dealloc {
    [self.locationManager stopUpdatingLocation];
    [self.locationManager stopUpdatingHeading];
    self.locationManager.delegate = nil;
    self.locationManager = nil;
    
    self.lastRecordedLocation = nil;
    self.locationHistory = nil;
    self.speedHistory = nil;
}

- (void)setSignalStrength:(PSLocationManagerGPSSignalStrength)signalStrength {
    BOOL needToUpdateDelegate = NO;
    if (_signalStrength != signalStrength) {
        needToUpdateDelegate = YES;
    }
    
    _signalStrength = signalStrength;
    
    if (self.signalStrength == PSLocationManagerGPSSignalStrengthStrong) {
        self.allowMaximumAcceptableAccuracy = NO;
    } else if (self.signalStrength == PSLocationManagerGPSSignalStrengthWeak) {
        [self checkSustainedSignalStrength];
    }
        
    if (needToUpdateDelegate) {
        if ([self.delegate respondsToSelector:@selector(locationManager:signalStrengthChanged:)]) {
            [self.delegate locationManager:self signalStrengthChanged:self.signalStrength];
        }
    }
}

- (void)setTotalDistance:(CLLocationDistance)totalDistance {
    _totalDistance = totalDistance;
    
    if (self.currentSpeed != kSpeedNotSet) {
        if ([self.delegate respondsToSelector:@selector(locationManager:distanceUpdated:)]) {
            [self.delegate locationManager:self distanceUpdated:self.totalDistance];
        }
    }
}

- (NSTimeInterval)totalSeconds {
    return ([self.startTimestamp timeIntervalSinceNow] * -1) - self.pauseDelta;
}

- (void)checkSustainedSignalStrength {
    if (!self.checkingSignalStrength) {
        self.checkingSignalStrength = YES;
        
        double delayInSeconds = kGPSRefinementInterval;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            self.checkingSignalStrength = NO;
            if (self.signalStrength == PSLocationManagerGPSSignalStrengthWeak) {
                self.allowMaximumAcceptableAccuracy = YES;
                if ([self.delegate respondsToSelector:@selector(locationManagerSignalConsistentlyWeak:)]) {
                    [self.delegate locationManagerSignalConsistentlyWeak:self];
                }
            } else if (self.signalStrength == PSLocationManagerGPSSignalStrengthInvalid) {
                self.allowMaximumAcceptableAccuracy = YES;
                self.signalStrength = PSLocationManagerGPSSignalStrengthWeak;
                if ([self.delegate respondsToSelector:@selector(locationManagerSignalConsistentlyWeak:)]) {
                    [self.delegate locationManagerSignalConsistentlyWeak:self];
                }
            }
        });
    }
}

- (void)requestNewLocation {
    [self.locationManager stopUpdatingLocation];
    [self.locationManager startUpdatingLocation];
}

- (BOOL)prepLocationUpdates {
    if ([CLLocationManager locationServicesEnabled]) {
        [self.locationHistory removeAllObjects];
        [self.speedHistory removeAllObjects];
        self.lastDistanceAndSpeedCalculation = 0;
        self.currentSpeed = kSpeedNotSet;
        self.readyToExposeDistanceAndSpeed = NO;
        self.signalStrength = PSLocationManagerGPSSignalStrengthInvalid;
        self.allowMaximumAcceptableAccuracy = NO;
        
        self.forceDistanceAndSpeedCalculation = YES;
        [self.locationManager startUpdatingLocation];
        [self.locationManager startUpdatingHeading];
        
        [self checkSustainedSignalStrength];
        
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)startLocationUpdates {
    if ([CLLocationManager locationServicesEnabled]) {
        self.readyToExposeDistanceAndSpeed = YES;
        
        [self.locationManager startUpdatingLocation];
        [self.locationManager startUpdatingHeading];
        
        if (self.pauseDeltaStart > 0) {
            self.pauseDelta += ([NSDate timeIntervalSinceReferenceDate] - self.pauseDeltaStart);
            self.pauseDeltaStart = 0;
        }
        
        return YES;
    } else {
        return NO;
    }
}

- (void)stopLocationUpdates {
    [self.locationPingTimer invalidate];
    [self.locationManager stopUpdatingLocation];
    [self.locationManager stopUpdatingHeading];
    self.pauseDeltaStart = [NSDate timeIntervalSinceReferenceDate];
    self.lastRecordedLocation = nil;
}

- (void)resetLocationUpdates {
    self.totalDistance = 0;
    self.startTimestamp = [NSDate dateWithTimeIntervalSinceNow:0];
    self.forceDistanceAndSpeedCalculation = NO;
    self.pauseDelta = 0;
    self.pauseDeltaStart = 0;
}

#pragma mark CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation {
    // since the oldLocation might be from some previous use of core location, we need to make sure we're getting data from this run
    if (oldLocation == nil) return;
    BOOL isStaleLocation = ([oldLocation.timestamp compare:self.startTimestamp] == NSOrderedAscending);
    
    [self.locationPingTimer invalidate];
    
    if (newLocation.horizontalAccuracy <= kRequiredHorizontalAccuracy) {
        self.signalStrength = PSLocationManagerGPSSignalStrengthStrong;
    } else {
        self.signalStrength = PSLocationManagerGPSSignalStrengthWeak;
    }
    
    double horizontalAccuracy;
    if (self.allowMaximumAcceptableAccuracy) {
        horizontalAccuracy = kMaximumAcceptableHorizontalAccuracy;
    } else {
        horizontalAccuracy = kRequiredHorizontalAccuracy;
    }
    
    if (!isStaleLocation && newLocation.horizontalAccuracy >= 0 && newLocation.horizontalAccuracy <= horizontalAccuracy) {
        
        [self.locationHistory addObject:newLocation];
        if ([self.locationHistory count] > kNumLocationHistoriesToKeep) {
            [self.locationHistory removeObjectAtIndex:0];
        }
        
        BOOL canUpdateDistanceAndSpeed = NO;
        if ([self.locationHistory count] >= kMinLocationsNeededToUpdateDistanceAndSpeed) {
            canUpdateDistanceAndSpeed = YES && self.readyToExposeDistanceAndSpeed;
        }
        
        if (self.forceDistanceAndSpeedCalculation || [NSDate timeIntervalSinceReferenceDate] - self.lastDistanceAndSpeedCalculation > kDistanceAndSpeedCalculationInterval) {
            self.forceDistanceAndSpeedCalculation = NO;
            self.lastDistanceAndSpeedCalculation = [NSDate timeIntervalSinceReferenceDate];
            
            CLLocation *lastLocation = (self.lastRecordedLocation != nil) ? self.lastRecordedLocation : oldLocation;
            
            CLLocation *bestLocation = nil;
            CGFloat bestAccuracy = kRequiredHorizontalAccuracy;
            for (CLLocation *location in self.locationHistory) {
                if ([NSDate timeIntervalSinceReferenceDate] - [location.timestamp timeIntervalSinceReferenceDate] <= kValidLocationHistoryDeltaInterval) {
                    if (location.horizontalAccuracy <= bestAccuracy && location != lastLocation) {
                        bestAccuracy = location.horizontalAccuracy;
                        bestLocation = location;
                    }
                }
            }
            if (bestLocation == nil) bestLocation = newLocation;
            
            CLLocationDistance distance = [bestLocation distanceFromLocation:lastLocation];
            if (canUpdateDistanceAndSpeed) self.totalDistance += distance;
            self.lastRecordedLocation = bestLocation;
            
            NSTimeInterval timeSinceLastLocation = [bestLocation.timestamp timeIntervalSinceDate:lastLocation.timestamp];
            if (timeSinceLastLocation > 0) {
                CGFloat speed = distance / timeSinceLastLocation;
                if (speed <= 0 && [self.speedHistory count] == 0) {
                    // don't add a speed of 0 as the first item, since it just means we're not moving yet
                } else {
                    [self.speedHistory addObject:[NSNumber numberWithDouble:speed]];
                }
                if ([self.speedHistory count] > kNumSpeedHistoriesToAverage) {
                    [self.speedHistory removeObjectAtIndex:0];
                }
                if ([self.speedHistory count] > 1) {
                    double totalSpeed = 0;
                    for (NSNumber *speedNumber in self.speedHistory) {
                        totalSpeed += [speedNumber doubleValue];
                    }
                    if (canUpdateDistanceAndSpeed) {
                        double newSpeed = totalSpeed / (double)[self.speedHistory count];
                        if (kPrioritizeFasterSpeeds > 0 && speed > newSpeed) {
                            newSpeed = speed;
                            [self.speedHistory removeAllObjects];
                            for (int i=0; i<kNumSpeedHistoriesToAverage; i++) {
                                [self.speedHistory addObject:[NSNumber numberWithDouble:newSpeed]];
                            }
                        }
                        self.currentSpeed = newSpeed;
                    }
                }
            }
            
            if ([self.delegate respondsToSelector:@selector(locationManager:waypoint:calculatedSpeed:)]) {
                [self.delegate locationManager:self waypoint:self.lastRecordedLocation calculatedSpeed:self.currentSpeed];
            }
        }
    }
    
    // this will be invalidated above if a new location is received before it fires
    self.locationPingTimer = [NSTimer timerWithTimeInterval:kMinimumLocationUpdateInterval target:self selector:@selector(requestNewLocation) userInfo:nil repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:self.locationPingTimer forMode:NSRunLoopCommonModes];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading {
    // we don't really care about the new heading.  all we care about is calculating the current distance from the previous distance early if the user changed directions
    self.forceDistanceAndSpeedCalculation = YES;
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    if (error.code == kCLErrorDenied) {
        if ([self.delegate respondsToSelector:@selector(locationManager:error:)]) {
            [self.delegate locationManager:self error:error];
        }
        [self stopLocationUpdates];
    }
}

@end
