//
//  LocationManager.h
//  Faster
//
//  Created by Daniel Isenhower on 1/6/12.
//  Copyright (c) 2012 PerspecDev Solutions LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@class PSLocationManager;

typedef enum {
    PSLocationManagerGPSSignalStrengthInvalid = 0
    , PSLocationManagerGPSSignalStrengthWeak
    , PSLocationManagerGPSSignalStrengthStrong
} PSLocationManagerGPSSignalStrength;

@protocol PSLocationManagerDelegate <NSObject>

@optional
- (void)locationManager:(PSLocationManager *)locationManager signalStrengthChanged:(PSLocationManagerGPSSignalStrength)signalStrength;
- (void)locationManagerSignalConsistentlyWeak:(PSLocationManager *)locationManager;
- (void)locationManager:(PSLocationManager *)locationManager distanceUpdated:(CLLocationDistance)distance;
- (void)locationManager:(PSLocationManager *)locationManager waypoint:(CLLocation *)waypoint calculatedSpeed:(double)calculatedSpeed;
- (void)locationManager:(PSLocationManager *)locationManager error:(NSError *)error;
- (void)locationManager:(PSLocationManager *)locationManager debugText:(NSString *)text;

@end

@interface PSLocationManager : NSObject <CLLocationManagerDelegate>

@property (nonatomic, weak) id<PSLocationManagerDelegate> delegate;
@property (nonatomic, readonly) PSLocationManagerGPSSignalStrength signalStrength;
@property (nonatomic, readonly) CLLocationDistance totalDistance;
@property (nonatomic, readonly) NSTimeInterval totalSeconds;
@property (nonatomic, readonly) double currentSpeed;

+ (PSLocationManager *)sharedLocationManager;

- (BOOL)prepLocationUpdates; // this must be called before startLocationUpdates (best to call it early so we can get an early lock on location)
- (BOOL)startLocationUpdates;
- (void)stopLocationUpdates;
- (void)resetLocationUpdates;

@end
