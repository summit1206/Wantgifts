/***************
 RootViewController.h
 Copyright 2010-2016 Robert T. Miller
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 *****************/

//
//  RootViewController.h
//  rTracker
//
//  This is the first interactive screen, showing a list of the available trackers plus
// top:
//  - button to add a new tracker
//  - button to edit the list of available trackers
//
// bottom:
//  - pay button
//  - button to set privacy level
//  - button to graph multiple trackers together
//  - ??? export button ???
//
//  Created by Robert Miller on 16/03/2010.
//  Copyright Robert T. Miller 2010. All rights reserved.
//

#import "trackerList.h"
#import "dbg-defs.h"
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
@class privacyV;

#if ADVERSION
#import "adSupport.h"
@interface RootViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, ADBannerViewDelegate>
#else
@interface RootViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
#endif
/*
 {

	trackerList *tlist;
	privacyV *privacyObj;
    int32_t refreshLock;
    BOOL initialPrefsLoad;
    NSNumber *stashedPriv;
    //BOOL openUrlLock;
    //NSURL *inputURL;
    BOOL readingFile;
    NSMutableArray *stashedTIDs;
    NSMutableDictionary *scheduledReminderCounts;
}
*/

@property (nonatomic, strong) UITableView *tableView;

@property (nonatomic,strong) trackerList *tlist;
@property (nonatomic, strong) privacyV *privacyObj;
@property (atomic) int32_t refreshLock;
@property (nonatomic) BOOL initialPrefsLoad;
//@property (nonatomic) BOOL openUrlLock;
//@property (nonatomic,retain) NSURL *inputURL;
@property (nonatomic) BOOL readingFile;
@property (nonatomic,strong) NSMutableArray *stashedTIDs;
@property (nonatomic,strong) NSMutableDictionary *scheduledReminderCounts;

// UI element properties 
@property (nonatomic, strong) UIBarButtonItem *privateBtn;
@property (nonatomic, strong) UIBarButtonItem *helpBtn;
@property (nonatomic, strong) UIBarButtonItem *addBtn;
@property (nonatomic, strong) UIBarButtonItem *editBtn;
@property (nonatomic, strong) UIBarButtonItem *flexibleSpaceButtonItem;

// Weather View
@property (nonatomic, retain) CLLocationManager *locationManager;
@property (nonatomic, retain) CLLocation *currentLocation;
@property (nonatomic, assign)  CLLocationCoordinate2D Weather2d;

#if ADVERSION
@property (nonatomic,strong) adSupport *adSupport;
#endif

//@property (nonatomic, retain) UIBarButtonItem *multiGraphBtn;
//@property (nonatomic, retain) UIBarButtonItem *payBtn;

//- (void)applicationWillTerminate:(NSNotification *)notification;

- (void) loadInputFiles;
- (void) refreshView;
- (void) refreshToolBar:(BOOL)animated;
- (void) refreshEditBtn;
- (int) handleOpenFileURL:(NSURL*)url tname:(NSString*)tname;
- (BOOL) exceedsPrivacy:(NSInteger)tid;
- (void) openTracker:(NSInteger)tid rejectable:(BOOL)rejectable;
- (void) doOpenTracker:(NSNumber*)nsnTid;

//- (void) jumpMaxPriv;
//- (void) restorePriv;

- (void) startRvcActivityIndicator;
- (void) finishRvcActivityIndicator;

- (NSInteger) pendingNotificationCount;

@end
