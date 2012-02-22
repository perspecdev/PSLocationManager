//
//  ViewController.h
//  PSLocationManager
//
//  Created by Daniel Isenhower on 2/22/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "PSLocationManager.h"

@interface ViewController : UIViewController <PSLocationManagerDelegate>

@property (nonatomic, weak) IBOutlet UILabel *strengthLabel;
@property (nonatomic, weak) IBOutlet UILabel *distanceLabel;

@end
