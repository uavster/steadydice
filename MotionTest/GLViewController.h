//
//  GLViewController.h
//  MotionTest
//
//  Created by uavster on 7/23/13.
//  Copyright (c) 2013 uavster. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <GLKit/GLKit.h>
#import <opencv2/highgui/cap_ios.h>

@interface GLViewController : GLKViewController<CvVideoCameraDelegate>

@end
