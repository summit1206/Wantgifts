/***************
 RootViewController.m
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
//  RootViewController.m
//  rTracker
//
//  Created by Robert Miller on 16/03/2010.
//  Copyright Robert T. Miller 2010. All rights reserved.
//

#import <libkern/OSAtomic.h>

#import "RootViewController.h"
#import "rTrackerAppDelegate.h"
#import "addTrackerController.h"
#import "configTlistController.h"
#import "useTrackerController.h"
#import "rTracker-resource.h"
#import "privacyV.h"
#import "rTracker-constants.h"
#import "rTracker-resource.h"

#import "WeatherViewController.h"

#import "CSVParser.h"

#import "dbg-defs.h"

#if ADVERSION
#import "adSupport.h"
#import "rt_IAPHelper.h"
#endif

@implementation RootViewController

@synthesize tableView=_tableView;
@synthesize tlist=_tlist, refreshLock=_refreshLock;
@synthesize privateBtn=_privateBtn, helpBtn=_helpBtn, privacyObj=_privacyObj, addBtn=_addBtn, editBtn=_editBtn, flexibleSpaceButtonItem=_flexibleSpaceButtonItem, initialPrefsLoad=_initialPrefsLoad, readingFile=_readingFile, stashedTIDs=_stashedTIDs, scheduledReminderCounts=_scheduledReminderCounts;

#if ADVERSION
@synthesize adSupport=_adSupport;
#endif

//openUrlLock, inputURL,

#pragma mark -
#pragma mark core object methods and support

- (void)dealloc {
	
	DBGLog(@"rvc dealloc");
	//[privateBtn release]; // saved to change image
    //self.inputURL = nil;
    //[inputURL release];
    
}

/*
- (void)applicationWillTerminate:(NSNotification *)notification {
	DBGLog(@"rvc: app will terminate");
	// close trackerList
	
}
*/

#pragma mark -
#pragma mark load CSV files waiting for input

static int csvLoadCount;
static int plistLoadCount;
static int csvReadCount;
static int plistReadCount;
static BOOL InstallSamples;
static BOOL InstallDemos;

//
// original code:
//-------------------
//  Created by Matt Gallagher on 2009/11/30.
//  Copyright 2009 Matt Gallagher. All rights reserved.
//
//  Permission is given to use this source code file, free of charge, in any
//  project, commercial or otherwise, entirely at your risk, with the condition
//  that any redistribution (in part or whole) of source code must retain
//  this copyright and permission notice. Attribution in compiled projects is
//  appreciated but not required.
//-------------------

-(void) doCSVLoad:(NSString*)csvString to:(trackerObj*)to fname:(NSString*)fname {
    
    DBGLog(@"start csv parser %@",to.trackerName);
    CSVParser *parser = [[CSVParser alloc] initWithString:csvString separator:@"," hasHeader:YES fieldNames:nil];
    to.csvProblem=nil;
    to.csvReadFlags=0;
    [parser parseRowsForReceiver:to selector:@selector(receiveRecord:)]; // receiveRecord in trackerObj.m
    DBGLog(@"csv parser done %@",to.trackerName);
    
    //[to reloadVOtable];
    [to loadConfig];
    
    if (to.csvReadFlags & (CSVCREATEDVO | CSVCONFIGVO | CSVLOADRECORD)) {
        
        to.goRecalculate=YES;
        [to recalculateFns];    // updates fn vals in database
        to.goRecalculate=NO;
        DBGLog(@"functions recalculated %@",to.trackerName);
        
        [to saveChoiceConfigs]; // in case csv data had unrecognised choices
        
        DBGLog(@"csv loaded:");
#if DEBUGLOG
        [to describe];
#endif
    }
    if (to.csvReadFlags & CSVNOTIMESTAMP) {
        [rTracker_resource alert:@"No timestamp column" msg:[NSString stringWithFormat:@"The file %@ has been rejected by the CSV loader as it does not have '%@' as the first column.",fname,TIMESTAMP_LABEL] vc:self];
        [rTracker_resource finishActivityIndicator:self.view navItem:nil disable:NO];
        return;
    } else if (to.csvReadFlags & CSVNOREADDATE) {
        [rTracker_resource alert:@"Date format problem" msg:[NSString stringWithFormat:@"Some records in the file %@ were ignored because timestamp dates like '%@' are not compatible with your device's calendar settings (%@).  Please modify the file or change your international locale preferences in System Settings and try again.",fname,to.csvProblem,[to.dateFormatter stringFromDate:[NSDate date] ]] vc:self];
        [rTracker_resource finishActivityIndicator:self.view navItem:nil disable:NO];
        return;
    }
    
    [rTracker_resource setProgressVal:(((float)csvReadCount)/((float)csvLoadCount))];
    csvReadCount++;
    
    
}
-(void) startLoadActivityIndicator:(NSString*)str {
    [rTracker_resource startActivityIndicator:self.view navItem:nil disable:NO str:str];
}

- (void) loadTrackerCsvFiles {
    //DBGLog(@"loadTrackerCsvFiles");
    NSString *docsDir = [rTracker_resource ioFilePath:nil access:YES];
    NSFileManager *localFileManager=[NSFileManager defaultManager];
    NSDirectoryEnumerator *dirEnum = [localFileManager enumeratorAtPath:docsDir];
    BOOL newRtcsvTracker=NO;
    BOOL rtcsv=NO;
    
    NSString *file;

    //[self jumpMaxPriv];
    [privacyV jumpMaxPriv];
    while ((file = [dirEnum nextObject])) {
        trackerObj *to = nil;
        NSString *fname = [file lastPathComponent];
        NSString *tname = nil;
        NSRange inmatch;
        BOOL validMatch=NO;
        NSString *loadObj;
        
        if ([[file pathExtension] isEqualToString: @"csv"]) {
            loadObj = @"csv";
            inmatch = [fname rangeOfString:@"_in.csv" options:NSBackwardsSearch|NSAnchoredSearch];
            //DBGLog(@"consider input: %@",fname);
            
            if ((inmatch.location != NSNotFound) && (inmatch.length == 7)) {  // matched all 7 chars of _in.csv at end of file name  (must test not _out.csv)
                validMatch=YES;
            }
            
        } else if ([[file pathExtension] isEqualToString: @"rtcsv"]) {
            rtcsv=YES;
            loadObj = @"rtcsv";
            
            inmatch = [fname rangeOfString:@".rtcsv" options:NSBackwardsSearch|NSAnchoredSearch];
            //DBGLog(@"consider input: %@",fname);
            
            if ((inmatch.location != NSNotFound) && (inmatch.length == 6)) {  // matched all 6 chars of .rtcsv at end of file name  (unlikely to fail but need inmatch to get tname)
                validMatch=YES;
            }
        }

        if (validMatch) {
            DBGLog(@"%@ load input: %@ as %@",loadObj,fname,tname);

            tname = [fname substringToIndex:inmatch.location];
            NSInteger tid = [self.tlist getTIDfromName:tname];
            if (tid) {
                to = [[trackerObj alloc]init:tid];
                DBGLog(@" found existing tracker tid %ld with matching name",(long)tid);
            } else if (rtcsv) {
                to = [[trackerObj alloc] init];
                to.trackerName = tname;
                to.toid = [self.tlist getUnique];
                [to saveConfig];
                [self.tlist addToTopLayoutTable:to];
                newRtcsvTracker = YES;
                DBGLog(@"created new tracker for rtcsv, id= %ld",(long)to.toid);
            }

            if (nil != to) {
                [self performSelectorOnMainThread:@selector(startLoadActivityIndicator:) withObject:[NSString stringWithFormat:@"loading %@ %@",tname,loadObj] waitUntilDone:NO];

                NSString *target = [docsDir stringByAppendingPathComponent:file];
                NSString *csvString = [NSString stringWithContentsOfFile:target encoding:NSUTF8StringEncoding error:NULL];
                
                [rTracker_resource stashProgressBarMax:(int)[rTracker_resource countLines:csvString]];

                if (csvString)
                {
                    [UIApplication sharedApplication].idleTimerDisabled = YES;
                    [self doCSVLoad:csvString to:to fname:fname];
                    [UIApplication sharedApplication].idleTimerDisabled = NO;

                    [rTracker_resource deleteFileAtPath:target];
                }
                
                [rTracker_resource finishActivityIndicator:self.view navItem:nil disable:NO];
            }
            
        }
        
    }
    
    //[self restorePriv];
    [privacyV restorePriv];
    
    if (newRtcsvTracker) {
        [self refreshViewPart2];
    }
}


/*

if ([[file pathExtension] isEqualToString: @"csv"]) {
 
    inmatch = [fname rangeOfString:@"_in.csv" options:NSBackwardsSearch|NSAnchoredSearch];
    //DBGLog(@"consider input: %@",fname);
 
    if ((inmatch.location != NSNotFound) && (inmatch.length == 7)) {  // matched all 7 chars of _in.csv at end of file name
        validMatch=YES;
 
        tname = [fname substringToIndex:inmatch.location];
        DBGLog(@"csv load input: %@ as %@",fname,tname);
        //int ndx=0;
        
        for (NSString *tracker in self.tlist.topLayoutNames) {
            if ([tracker isEqualToString:tname]) {
                DBGLog(@"match to: %@",tracker);
                to = [[trackerObj alloc] init:[self.tlist getTIDfromName:tname]];  // accept will take first if multiple with same name
                
                NSString *target = [docsDir stringByAppendingPathComponent:file];
                NSString *csvString = [NSString stringWithContentsOfFile:target encoding:NSUTF8StringEncoding error:NULL];
                
                [rTracker_resource stashProgressBarMax:[rTracker_resource countLines:csvString]];
                
                if (csvString)
                {
                    [self doCSVLoad:csvString to:to fname:fname];
                    [rTracker_resource deleteFileAtPath:target];
                    
                }
                
                [to release];
                
                //ndx++;
            }
        }
    }
} else if ([[file pathExtension] isEqualToString: @"rtcsv"]) {
    rtcsv=YES;
    inmatch = [fname rangeOfString:@".rtcsv" options:NSBackwardsSearch|NSAnchoredSearch];
    //DBGLog(@"consider input: %@",fname);
    
    if ((inmatch.location != NSNotFound) && (inmatch.length == 6)) {  // matched all 6 chars of .rtcsv at end of file name  (unlikely to fail)
        validMatch=YES;
        
        NSString *tname = [fname substringToIndex:inmatch.location];
        
        
        
        [self performSelectorOnMainThread:@selector(startLoadCsvActivityIndicator:) withObject:tname waitUntilDone:NO];
        
        DBGLog(@"rtcsv load input: %@ as %@",fname,tname);
        trackerObj *to;
        int tid = [self.tlist getTIDfromName:tname];
        if (tid) {
            to = [[trackerObj alloc]init:tid];
            DBGLog(@" found existing tracker tid %d with matching name",tid);
        } else {
            to = [[trackerObj alloc] init];
            to.trackerName = tname;
            to.toid = [self.tlist getUnique];
            [to saveConfig];
            [self.tlist addToTopLayoutTable:to];
            newRtcsvTracker = YES;
        }
        
        NSString *target = [docsDir stringByAppendingPathComponent:file];
        
        NSString *csvString = [NSString stringWithContentsOfFile:target encoding:NSUTF8StringEncoding error:NULL];
        
        [rTracker_resource stashProgressBarMax:[rTracker_resource countLines:csvString]];
        
        if (csvString)
        {
            [self doCSVLoad:csvString to:to fname:fname];
            [rTracker_resource deleteFileAtPath:target];
            
        }
        
        [to release];
        
        [rTracker_resource finishActivityIndicator:self.view navItem:nil disable:NO];
        
        
    }
}
}
*/







// load a tracker from NSDictionary generated by trackerObj:dictFromTO()
//    [consists of tid, optDict and valObjTable]
//    if trackerName match
//      if different tid
//         change tid of existing to input new
//      merge new trackerObj:
//         update vids as needed
//         add valObjs as needed
//    else
//      if existing tid match
//         move existing to new tid
//      add new tracker
//
//  added nov 2012
//
- (int) loadTrackerDict:(NSDictionary*)tdict tname:(NSString*)tname {
    
    // get input tid
    NSNumber *newTID = tdict[@"tid"];
    DBGLog(@"load input: %@ tid %@",tname, newTID);
    
    int newTIDi = [newTID intValue];
    int matchTID = -1;
    NSArray *tida = [self.tlist getTIDFromNameDb:tname];
    
    // find tracker with same name and tid, or just same name
    for (NSNumber *tid in tida) {
        if ((-1 == matchTID) || ([tid isEqualToNumber:newTID])) // first tid with same name, or tid for matching name if exists
            matchTID = [tid intValue];
    }
    
    DBGLog(@"matchTID= %d",matchTID);
    
    trackerObj *inputTO;
    if (-1 != matchTID) {  // found tracker with same name and maybe same tid
        if (!loadingDemos) {
            [rTracker_resource stashTracker:matchTID];                            // make copy of current tracker so can reject newTID later
        }
        [self.tlist updateTID:matchTID new:newTIDi];                          // change existing tracker tid to match new (restore if we discard later)

        inputTO = [[trackerObj alloc] init:newTIDi];                          // load up existing tracker config
        
        [inputTO confirmTOdict:tdict];                                        // merge valObjs
        inputTO.prevTID = matchTID;
        [inputTO saveConfig];                                                 // write to db -- probably redundant as confirmTOdict writes to db as well
        
        DBGLog(@"updated %@",tname);
        
        //DBGLog(@"skip load plist file as already have %@",tname);
    } else {              // new tracker coming in
        [self.tlist fixDictTID:tdict];                                        // move any existing TIDs out of way
        inputTO = [[trackerObj alloc] initWithDict:tdict];                    // create new tracker with input data
        inputTO.prevTID = matchTID;
        [inputTO saveConfig];                                                 // write to db
        [self.tlist addToTopLayoutTable:inputTO];                             // insert in top list
        DBGLog(@"loaded new %@",tname);        
    }
    
    
    return newTIDi;
}

#pragma mark -
#pragma mark load .plists and .rtrks for input trackers

- (int) handleOpenFileURL:(NSURL*)url tname:(NSString*)tname {
    NSDictionary *tdict = nil;
    NSDictionary *dataDict = nil;
    int tid;
    NSString *objName;
    
    DBGLog(@"open url %@",url);
    /*
     // was needed when called for arbitrary url
    if ([@"rtcsv" isEqualToString:[url pathExtension]]) {
        [self loadTrackerCsvFiles];
        return 0;
    }
    */
    
    //[self jumpMaxPriv];
    [privacyV jumpMaxPriv];
    if (nil != tname) {  // if tname set it is just a plist
        tdict = [NSDictionary dictionaryWithContentsOfURL:url];
        objName = @"plist";
    } else {  // else is an rtrk
        NSDictionary *rtdict = [NSDictionary dictionaryWithContentsOfURL:url];
        tname = rtdict[@"trackerName"];
        tdict = rtdict[@"configDict"];
        dataDict = rtdict[@"dataDict"];
        objName = @"rtrk";
        if (loadingDemos) {
            [self.tlist deleteTrackerAllTID:[tdict objectForKey:@"tid"] name:tname];  // wipe old demo tracker otherwise starts to look ugly
        }
    }

    int c = (int) [(NSArray *)tdict[@"valObjTable"] count];
    int c2 = (nil == dataDict ? 0 : (int) [dataDict count]);
    if ((c>20) || (c2>20))
        [self performSelectorOnMainThread:@selector(startLoadActivityIndicator:) withObject:[NSString stringWithFormat:@"loading %@ %@",tname,objName] waitUntilDone:NO];
    
    //DBGLog(@"ltd enter dict= %lu",(unsigned long)[tdict count]);
    tid = [self loadTrackerDict:tdict tname:tname];

    if (nil != dataDict) {
        trackerObj *to = [[trackerObj alloc] init:tid];
        
        [to loadDataDict:dataDict];  // vids ok because confirmTOdict updated as needed
        to.goRecalculate=YES;
        [to recalculateFns];    // updates fn vals in database
        to.goRecalculate=NO;
        [to saveChoiceConfigs]; // in case input data had unrecognised choices
        
        DBGLog(@"datadict loaded for open file url:");
#if DEBUGLOG
        [to describe];
#endif
    }

    DBGLog(@"ltd/ldd finish");
    
    //[self.privacyObj setPrivacyValue:currPriv];                           // restore after jump to max
    //[self restorePriv];
    [privacyV restorePriv];
    DBGLog(@"removing file %@",[url path]);
    [rTracker_resource deleteFileAtPath:[url path]];
    //if ((c>20) || (c2>20))
        [rTracker_resource finishActivityIndicator:self.view navItem:nil disable:NO];
    
    
    return tid;
}


- (BOOL) loadTrackerPlistFiles {
    // called on refresh, loads any _in.plist files as trackers
    // also called if any .rtrk files exist
    DBGLog(@"loadTrackerPlistFiles");
    int rtrkTid=0;
    
    NSString *docsDir = [rTracker_resource ioFilePath:nil access:YES];
    NSFileManager *localFileManager= [NSFileManager defaultManager];
    NSDirectoryEnumerator *dirEnum = [localFileManager enumeratorAtPath:docsDir];
    
    NSString *file;
    
    NSMutableArray *filesToProcess = [[NSMutableArray alloc] init];
    while ((file = [dirEnum nextObject])) {
        NSString *fname = [file lastPathComponent];
        if ([[file pathExtension] isEqualToString: @"plist"]) {
            NSRange inmatch = [fname rangeOfString:@"_in.plist" options:NSBackwardsSearch|NSAnchoredSearch];
            //DBGLog(@"consider input: %@",fname);
            if ((inmatch.location != NSNotFound) && (inmatch.length == 9)) {  // matched all 9 chars of _in.plist at end of file name
                [filesToProcess addObject:file];
            }
        } else if ([[file pathExtension] isEqualToString: @"rtrk"]) {
/*
            NSRange inmatch = [fname rangeOfString:@"_out.rtrk" options:NSBackwardsSearch|NSAnchoredSearch];
            //DBGLog(@"consider input: %@",fname);
            if ((inmatch.location != NSNotFound) && (inmatch.length == 9)) {  // matched all 9 chars of _out.rtrk at end of file name
 
            } else {
*/
                [filesToProcess addObject:file];
/*
            }
*/
        }
    }
    
    for (file in filesToProcess) {
        //NSString *tname = nil;
        NSString *target;
        NSString *newTarget;
        BOOL plistFile=NO;
        
        NSString *fname = [file lastPathComponent];
        DBGLog(@"process input: %@",fname);

        target = [docsDir stringByAppendingPathComponent:file];
        
        newTarget = [[target stringByAppendingString:@"_reading"] stringByReplacingOccurrencesOfString:@"Documents/Inbox/" withString:@"Documents/"];
        
        NSError *err;
        if ([localFileManager moveItemAtPath:target toPath:newTarget error:&err] != YES)
            DBGErr(@"Error on move %@ to %@: %@",target, newTarget, err);

        self.readingFile=YES;
        
        NSRange inmatch = [fname rangeOfString:@"_in.plist" options:NSBackwardsSearch|NSAnchoredSearch];

        [UIApplication sharedApplication].idleTimerDisabled = YES;

        if ((inmatch.location != NSNotFound) && (inmatch.length == 9)) {  // matched all 9 chars of _in.plist at end of file name
            rtrkTid = [self handleOpenFileURL:[NSURL fileURLWithPath:newTarget] tname:[fname substringToIndex:inmatch.location]];
            plistFile = YES;
            //TODO:need to delete stash file now!!!
            //tname = [fname substringToIndex:inmatch.location];
            //tdict = [NSDictionary dictionaryWithContentsOfFile:newTarget];
            // [rTracker_resource deleteFileAtPath:newTarget];  -- done by handleOpenFileUrl
        } else {   // .rtrk file
            rtrkTid = [self handleOpenFileURL:[NSURL fileURLWithPath:newTarget] tname:nil];
            /*
            NSDictionary *rtdict = [NSDictionary dictionaryWithContentsOfFile:newTarget];
            tname = [rtdict objectForKey:@"trackerName"];
            tdict = [rtdict objectForKey:@"configDict"];
            dataDict = [rtdict objectForKey:@"dataDict"];
             */
        }

        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        if (plistFile) {
            [rTracker_resource rmStashedTracker:0];  // 0 means rm last stashed tracker, in this case the one stashed by handleOpenFileURL
        } else {
            [self.stashedTIDs addObject:@(rtrkTid)];
        }
        
        self.readingFile=NO;
    
        [rTracker_resource setProgressVal:(((float)plistReadCount)/((float)plistLoadCount))];
        plistReadCount++;

    }
/*
 old version below....
    
    while ((file = [dirEnum nextObject])) {
        if ([[file pathExtension] isEqualToString: @"plist"]) {
            NSString *fname = [file lastPathComponent];
            NSRange inmatch = [fname rangeOfString:@"_in.plist" options:NSBackwardsSearch|NSAnchoredSearch];
            DBGLog(@"consider input: %@",fname);
            
            if (inmatch.location == NSNotFound) {
                
            } else if (inmatch.length == 9) {  // matched all 9 chars of _in.plist at end of file name
                NSString *tname = [fname substringToIndex:inmatch.location];
                NSString *target = [docsDir stringByAppendingPathComponent:file];

                NSDictionary *tdict = [NSDictionary dictionaryWithContentsOfFile:target];

                // modified nov 2012 to use loadTrackerDict,
                // behaviour change is now handle matching trackerName

                [self loadTrackerDict:tdict tname:tname];
                didSomething= YES;

                [rTracker_resource setProgressVal:(((float)plistReadCount)/((float)plistLoadCount))];
                plistReadCount++;

                NSError *err;
                // apparently cannot rename in but can delete from application's Document folder
                // problem is during dirEnum ?
                BOOL rslt = [localFileManager removeItemAtPath:target error:&err];
                if (!rslt) {
                    DBGLog(@"Error: %@", err);
                }
            }
            
        } else if ([[file pathExtension] isEqualToString: @"rtrk"]) {
            NSString *target = [docsDir stringByAppendingPathComponent:file];            
            NSDictionary *rtdict = [NSDictionary dictionaryWithContentsOfFile:target];
            
        }
    }
 */
      // added 13 feb 2013
    // not the default manager [localFileManager release];
    return(rtrkTid);
}

BOOL loadingCsvFiles=NO;

- (void) doLoadCsvFiles {
    if (loadingCsvFiles) return;
    loadingCsvFiles=YES;
    @autoreleasepool {
    
        [UIApplication sharedApplication].idleTimerDisabled = YES;
        [self loadTrackerCsvFiles];
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        // file load done, enable userInteraction
        [rTracker_resource finishProgressBar:self.view navItem:self.navigationItem disable:YES];
        [rTracker_resource finishActivityIndicator:self.view navItem:self.navigationItem disable:YES];
        
        // give up lock
        self.refreshLock = 0;
        loadingCsvFiles=NO;
        dispatch_async(dispatch_get_main_queue(), ^(void){
            [self refreshToolBar:YES];
        });
        DBGLog(@"csv data loaded, UI enabled, lock off stashedTIDs= %@",self.stashedTIDs);
        
        if (0< [self.stashedTIDs count]) {
            [self doRejectableTracker];
        }
    

    }
    
    // thread finished
}

- (void) refreshViewPart2 {
    //DBGLog(@"entry");
	[self.tlist loadTopLayoutTable];
    dispatch_async(dispatch_get_main_queue(), ^(void){
        [self.tableView reloadData];
        [self refreshEditBtn];
        [self refreshToolBar:YES];
        [self.view setNeedsDisplay];
    });
    // no effect [self.tableView setNeedsDisplay];
}

BOOL loadingInputFiles=NO;
- (void) doLoadInputfiles {
    if (loadingInputFiles) return;
    if (loadingCsvFiles) return;
    loadingInputFiles=YES;
    @autoreleasepool {
    
        if (InstallDemos) {
            [self loadDemos:YES];
            InstallDemos = NO;
        }
        
        if (InstallSamples) {
            [self loadSamples:YES];
            InstallSamples = NO;
        }
        
        if ([self loadTrackerPlistFiles]) {
            // this thread now completes updating rvc display of trackerList as next step is load csv data and trackerlist won't change
            [self.tlist loadTopLayoutTable];  // called again in refreshviewpart2, but need for re-order to set ranks
            [self.tlist reorderFromTLT];
        };
        
        [self refreshViewPart2];
        
        [NSThread detachNewThreadSelector:@selector(doLoadCsvFiles) toTarget:self withObject:nil];
        
        DBGLog(@"load plist thread finished, lock still on, UI still disabled");
        loadingInputFiles=NO;
    }
    // end of this thread, refreshLock still on, userInteraction disabled, activityIndicator still spinning and doLoadCsvFiles is in charge
}

- (int) countInputFiles:(NSString*)targ_ext {
    int retval = 0;
    
    NSString *docsDir = [rTracker_resource ioFilePath:nil access:YES];
    NSFileManager *localFileManager=[NSFileManager defaultManager];
    NSDirectoryEnumerator *dirEnum = [localFileManager enumeratorAtPath:docsDir];
        
    NSString *file;
        
    while (file = [dirEnum nextObject]) {
        NSString *fname = [file lastPathComponent];
        //DBGLog(@"consider input file %@",fname);
        NSRange inmatch = [fname rangeOfString:targ_ext options:NSBackwardsSearch|NSAnchoredSearch];
        if (inmatch.location != NSNotFound) {
            DBGLog(@"existsInputFiles: match on %@",fname);
            retval++;
        }
    }

    return retval;
}

- (void) loadInputFiles {
    if (loadingInputFiles) return;
    if (loadingCsvFiles) return;
    //if (!self.openUrlLock) {
        csvLoadCount = [self countInputFiles:@"_in.csv"];
        plistLoadCount = [self countInputFiles:@"_in.plist"];
        int rtrkLoadCount = [self countInputFiles:@".rtrk"];
        csvLoadCount += [self countInputFiles:@".rtcsv"];   //TODO: rtm here
        
        /*
         #if RTRK_EXPORT
         int rtrk_out = [self countInputFiles:@"_out.rtrk"];
         rtrkLoadCount -= rtrk_out;
         #endif
         */
        // handle rtrks as plist + csv, just faster if only has data or only has tracker def
        csvLoadCount += rtrkLoadCount;
        plistLoadCount += rtrkLoadCount;
        
        if (InstallSamples)
            plistLoadCount += [self loadSamples:NO];
        if (InstallDemos)
            plistLoadCount += [self loadDemos:NO];
    
        // set rvc:static numerators for progress bars
        csvReadCount=1;
        plistReadCount=1;
        
        if ( 0 < (plistLoadCount + csvLoadCount) ) {
            [self.tableView scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:YES];  // ScrollToTop so can see bars
            // CGRect navframe = [[self.navigationController navigationBar] frame]; // (navframe.size.height + navframe.origin.y)
            [rTracker_resource startProgressBar:self.view navItem:self.navigationItem disable:YES  yloc:0.0f];
            
            [NSThread detachNewThreadSelector:@selector(doLoadInputfiles) toTarget:self withObject:nil];
            // lock stays on, userInteraction disabled, activityIndicator spinning,   give up and doLoadInputFiles() is in charge
            
            DBGLog(@"returning main thread, lock on, UI disabled, activity spinning,  files to load");
            return;
        }
    //}
    [self refreshViewPart2];
    // if here, no files to load, this thread set the lock and refresh is done now 
    self.refreshLock = 0;
    DBGLog(@"finished, no files to load - lock off");
    
    return;
}

#define SUPPLY_DEMOS 0
#define SUPPLY_SAMPLES 1

-(int) loadSuppliedTrackers:(BOOL)doLoad set:(NSInteger)set {
    NSBundle *bundle = [NSBundle mainBundle];
    NSArray *paths;
    if (SUPPLY_DEMOS == set) {
        paths = [bundle pathsForResourcesOfType:@"plist" inDirectory:@"demoTrackers"];
    } else {
        paths = [bundle pathsForResourcesOfType:@"plist" inDirectory:@"sampleTrackers"];
    }
    int count=0;
    
    /* copy plists over version
     NSString *docsDir = [rTracker_resource ioFilePath:nil access:YES];
     NSFileManager *dfltManager = [NSFileManager defaultManager];
     */
    
    //DBGLog(@"paths %@",paths  );
    
    
    for (NSString *p in paths) {
        
        if (doLoad) {
            
            /*
             // copy plists over version -- doesn't handle conflicts
             NSString *fname = [p lastPathComponent];
             NSString *dest = [docsDir stringByAppendingFormat:@"/%@",fname];
             NSError *err = [[NSError alloc] init];
             if (!([dfltManager copyItemAtPath:p toPath:dest error:&err])) {
             DBGLog(@"copy failed  src= %@  dest= %@",p,docsDir);
             DBGLog(@"err: %@ %@ ",err.domain, err.helpAnchor);
             }
             */
            // /*

            // load now into trackerObj - needs progressBar
            NSDictionary *tdict = [NSDictionary dictionaryWithContentsOfFile:p];
            [self.tlist fixDictTID:tdict];
            trackerObj *newTracker = [[trackerObj alloc] initWithDict:tdict];
            
            [self.tlist deConflict:newTracker];  // add _n to trackerName so we don't overwrite user's existing if any .. could just merge now?
            
            [newTracker saveConfig];
            [self.tlist addToTopLayoutTable:newTracker];
            
            [rTracker_resource setProgressVal:(((float)plistReadCount)/((float)plistLoadCount))];
            plistReadCount++;

            // */
            
            DBGLog(@"finished loadSample on %@",p);
        }
        count++;
    }
    
    if (doLoad) {
        NSString *sql;
        if (SUPPLY_DEMOS == set) {
            sql = [NSString stringWithFormat:@"insert or replace into info (val, name) values (%i,'demos_version')",DEMOS_VERSION];
        } else {
            sql = [NSString stringWithFormat:@"insert or replace into info (val, name) values (%i,'samples_version')",SAMPLES_VERSION];
        }
        [self.tlist toExecSql:sql];
    }
    
    return(count);
    
}

- (int) loadSamples:(BOOL)doLoad {
    // called when handlePrefs decides is needed, copies plist files to documents dir
    // also called with doLoad=NO to just count
    // returns count
    
    int count = [self loadSuppliedTrackers:doLoad set:SUPPLY_SAMPLES];
    /*  // loadSuppliedTrackers does this (but that is not called for demos)
    if (doLoad && count) {
        NSString *sql;
        sql = [NSString stringWithFormat:@"insert or replace into info (val, name) values (%i,'samples_version')",SAMPLES_VERSION];
        [self.tlist toExecSql:sql];
    }
    */

    return count;
}

/*
- (void) deleteDemos {
     // already deleting in handleOpenFileURL, but there is a race condition ...
    
     NSString *tdName = @"👣rTracker demo";
     NSNumber *tdTid = [NSNumber numberWithInteger:[self.tlist getTIDfromName:tdName]];
     if (![tdTid isEqual:@0])
     [self.tlist deleteTrackerAllTID:tdTid name:tdName];

}
 */

- (int) loadDemos:(BOOL)doLoad {
    
    //return [self loadSuppliedTrackers:doLoad set:SUPPLY_DEMOS];
    NSString *newp;
    NSError *err;
    NSBundle *bundle = [NSBundle mainBundle];
    NSArray *paths = [bundle pathsForResourcesOfType:@"rtrk" inDirectory:@"demoTrackers"];
    int count=0;
    
    /*
     // just doesn't like touching inbox
    if (doLoad) { // confirm Inbox exists
        newp = [rTracker_resource ioFilePath:@"Inbox" access:YES];
        if  (![[NSFileManager defaultManager] createDirectoryAtPath:newp withIntermediateDirectories:YES attributes:nil error:&err] ) {
            DBGErr(@"Error creating dir : %@ error: %@", newp,  err);
        } else {
            DBGLog(@"created dir %@",newp);
        }
    }
    */
    loadingDemos=YES;
    for (NSString *p in paths) {
        if (doLoad) {
            NSString *file = [p lastPathComponent];
            //newp = [rTracker_resource ioFilePath:[NSString stringWithFormat:@"Inbox/%@",file] access:YES];
            newp = [rTracker_resource ioFilePath:[NSString stringWithFormat:@"%@",file] access:YES];
            if  (![[NSFileManager defaultManager] copyItemAtPath:p toPath:newp error:&err] ) {
                DBGErr(@"Error copying file: %@ to %@ error: %@", p, newp,  err);
                count--;
            } else {
                [self handleOpenFileURL:[NSURL fileURLWithPath:newp] tname:nil];
                //DBGLog(@"stashedTIDs= %@",self.stashedTIDs);

                //[rTracker_resource rmStashedTracker:0];  // 0 means rm last stashed tracker, in this case the one stashed by handleOpenFileURL //--> 2.0.6 deleting demo tracker before load so stash fails
            }
        }
        count++;
    }
    if (doLoad && count) {
        NSString *sql;
        sql = [NSString stringWithFormat:@"insert or replace into info (val, name) values (%i,'demos_version')",DEMOS_VERSION];
        [self.tlist toExecSql:sql];
    }
    loadingDemos=NO;
    return count;
}


#pragma mark -
#pragma mark view support

- (void)scrollState {
    if (_privacyObj && self.privacyObj.showing != PVNOSHOW) { // test backing ivar first -- don't instantiate if not there
        self.tableView.scrollEnabled = NO;
        //DBGLog(@"no");
    } else {
        self.tableView.scrollEnabled = YES;
        //DBGLog(@"yes");
    }
}

- (void) refreshToolBar:(BOOL)animated {
    //DBGLog(@"refresh tool bar, noshow= %d",(PVNOSHOW == self.privacyObj.showing));
    //DBGLog(@"refresh tool bar");
	[self setToolbarItems:@[self.flexibleSpaceButtonItem,
                           self.helpBtn,
						   //self.payBtn, 
                           self.privateBtn] 
				 animated:animated];
}

- (void) initTitle {
    
    // set up the title 
    
    NSString *devname = [[UIDevice currentDevice] name];
    //DBGLog(@"name = %@",devname);
    NSArray *words = [devname componentsSeparatedByString:@" "];
    
    NSUInteger i=0;
    NSUInteger c = [words count];
    NSString *name=nil;
    
    for (i=0;i<c && nil == name;i++) {
        NSString *w=nil;
        if (![@"" isEqual: (w = words[i])]) {
            name = w;
        }
    }
    
    NSUInteger prodNdx=0;
    NSString *longName = words[0];
    
    for (prodNdx =0; prodNdx<c;prodNdx++) {
        if ( (NSOrderedSame == [@"iphone" caseInsensitiveCompare:words[prodNdx]])
            || (NSOrderedSame == [@"ipad" caseInsensitiveCompare:words[prodNdx]])
            || (NSOrderedSame == [@"ipod" caseInsensitiveCompare:words[prodNdx]])
            || (NSOrderedSame == [@"itouch" caseInsensitiveCompare:words[prodNdx]]) ) {
            break;
        }
    }
    if ((1 <= prodNdx) && (prodNdx < c)) {
        for (i=1;i<prodNdx;i++) {
            longName = [longName stringByAppendingFormat:@" %@",words[i]];
        }
    } else if ((0 == prodNdx) || (prodNdx >= c)) {
            longName = nil;
    }
    
    //name= @"aiiiiiiiiiiiiiiiiiiiiii";
    

    if ((nil == name)
#if RELEASE
        || ([name isEqualToString:@"iPhone"])
        || ([name isEqualToString:@"iPad"])
#endif
        || (0 == [name length])
#if NONAME
        || YES
#endif
        ){
        self.title = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"]; // @"rTracker";
    } else {
        CGFloat bw1=0.0f;
        CGFloat bw2=0.0f;
        UIView *view = [self.editBtn valueForKey:@"view"];
        bw1 = view ? ([view frame].size.width + [view frame].origin.x) : (CGFloat)53.0; // hardcode after change from leftBarButton to backBarButton
        UIView *view2 = [self.addBtn valueForKey:@"view"];
        bw2 = view2 ? [view2 frame].origin.x : (CGFloat)282.0;

        if ((0.0f == bw1) || (0.0f==bw2)) {
            self.title = @"rTracker";
        } else {
            NSString *tname=nil,*tn2;

            NSRange r0 = [name rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"'`’´‘"] options:NSBackwardsSearch];
            if (NSNotFound != r0.location) {
                NSUInteger len = [name length];
                NSUInteger pos = r0.location + r0.length;
                if (pos == (len-1)) {
                    unichar c = [name characterAtIndex:pos];
                    if (('s' == c) || ('S' == c)) {
                        tname = [name stringByAppendingString:@" tracks"];
                        tn2 = [name stringByAppendingString:@"  tracks"];
                    }
                } else if (pos == len) {
                        tname = [name stringByAppendingString:@" tracks"];
                        tn2 = [name stringByAppendingString:@"  tracks"];
                }
            }
            
            if (nil == tname) {
                tname = [name stringByAppendingString:@"’s tracks"];
                tn2 = [name stringByAppendingString:@" ’s tracks"];
            }

            DBGLog(@"tname= %@",tname);
            DBGLog(@"longName= %@",longName);
            
            NSString *ltname = [longName stringByAppendingString:@" tracks"];
            NSString *ltn2 = [longName stringByAppendingString:@"  tracks"];
            
            CGFloat maxWidth = (bw2 - bw1)-8; //self.view.bounds.size.width - btnWidths;
            //DBGLog(@"view wid= %f bw1= %f bw2= %f",self.view.bounds.size.width ,bw1,bw2);
            //CGSize namesize = [tn2 sizeWithFont:[UIFont boldSystemFontOfSize:20.0f]]; //[tname sizeWithFont:[UIFont boldSystemFontOfSize:20.0f]];
            CGSize namesize = [tn2 sizeWithAttributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:20.0f]}];
            CGFloat nameWidth = ceilf( namesize.width );
            
            //CGSize lnamesize = [ltn2 sizeWithFont:[UIFont boldSystemFontOfSize:20.0f]]; //[tname sizeWithFont:[UIFont boldSystemFontOfSize:20.0f]];
            CGSize lnamesize = [ltn2 sizeWithAttributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:20.0f]}];

            CGFloat lnameWidth = ceilf( lnamesize.width );
            
            //DBGLog(@"name wid= %f  maxwid= %f  name= %@",nameWidth,maxWidth,tname);
            if ((nil != longName) && (lnameWidth < maxWidth)) {
                self.title = ltname;
            } else if (nameWidth < maxWidth) {
                self.title = tname;
            } else {
                self.title = @"rTracker";
            }
        }
    }
}


#if ADVERSION

- (void)viewDidLayoutSubviews
{
    if (![rTracker_resource getPurchased]) {
        [self.adSupport layoutAnimated:self tableview:self.tableView animated:[UIView areAnimationsEnabled]];
    }
}

- (void)bannerViewDidLoadAd:(ADBannerView *)banner
{
    [self.adSupport layoutAnimated:self tableview:self.tableView animated:YES];
}

- (void)bannerView:(ADBannerView *)banner didFailToReceiveAdWithError:(NSError *)error
{
    [self.adSupport layoutAnimated:self tableview:self.tableView animated:YES];
}

- (BOOL)bannerViewActionShouldBegin:(ADBannerView *)banner willLeaveApplication:(BOOL)willLeave
{
    //[self.adSupport stopTimer];
    return YES;
}
/*
- (void)bannerViewActionDidFinish:(ADBannerView *)banner
{
    //[self.adSupport startTimer];
}
*/

- (adSupport*) adSupport
{
    if (![rTracker_resource getPurchased]) {
        if (_adSupport == nil) {
            _adSupport = [[adSupport alloc] init];
        }
    }
    return _adSupport;
}

#endif
#pragma mark - CLLocationManager delegate methods

-(void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    if ([locations count]) {
        NSLog(@"Updated locations: %@", locations);
        if ([locations[0] isKindOfClass:[CLLocation class]]) {
            self.currentLocation = locations[0];
            self.Weather2d = self.currentLocation.coordinate;
            if(self.currentLocation.coordinate.latitude > 0.00 && self.currentLocation.coordinate.longitude > 0.00)
                [self.locationManager stopUpdatingLocation];
        }
    }
}
#pragma mark - Weather Config Actions
-(void)_alertWithTitle:(NSString *)title message:(NSString *)message {
    [[[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil] show];
}
//- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
//{
//
//}
-(void)GotoWeatherInfoViewAction:(UIButton *)sender {
    if(self.currentLocation.coordinate.latitude == 0.0 || self.currentLocation.coordinate.longitude == 0.0)
    {
        [self _alertWithTitle:@"Propmt" message:@"No current location found,Please check whether to run the app for location permission"];
        [self.locationManager startUpdatingLocation];
        return ;
    }else
    {
        WeatherViewController *weather = [[WeatherViewController alloc]init];
        weather.loaction = self.currentLocation;
        weather.lat = self.Weather2d.latitude;
        weather.lng = self.Weather2d.longitude;
        [self presentViewController:weather animated:YES completion:nil];
    }
}

- (void)viewDidLoad {
    
    [super viewDidLoad];

#if ADVERSION
#if !RELEASE
    [rTracker_resource setPurchased:NO];
#endif
    if (![rTracker_resource getPurchased]) {
#if !DISABLE_ADS
        [self.adSupport initBannerView:self];
#endif
    }
    //[self.view addSubview:self.adSupport.bannerView];
#endif
    
	//DBGLog(@"rvc: viewDidLoad privacy= %d",[privacyV getPrivacyValue]);
    //InstallSamples = NO;
    //InstallDemos = NO;
    self.refreshLock = 0;
    self.readingFile=NO;
    [self countScheduledReminders];

    //DBGLog(@"set backround image to %@",[rTracker_resource getLaunchImageName]);
    UIImageView *bg = [[UIImageView alloc] initWithImage:[UIImage imageNamed:[rTracker_resource getLaunchImageName]]];
    
    //[self.navigationController.view addSubview:bg];
    //[self.navigationController.view sendSubviewToBack:bg];
    self.navigationController.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:[rTracker_resource getLaunchImageName]]];
    
    
    //Weather Init
    self.locationManager = [CLLocationManager new];
    self.locationManager.delegate = self;
    if ([CLLocationManager authorizationStatus] != kCLAuthorizationStatusAuthorizedWhenInUse || [CLLocationManager authorizationStatus] != kCLAuthorizationStatusAuthorizedAlways) {
        [self.locationManager requestWhenInUseAuthorization];
    }
    self.locationManager.distanceFilter = kCLDistanceFilterNone;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters;
    [self.locationManager startUpdatingLocation];
   
    
    UIButton * button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:@"☁️"
            forState:UIControlStateNormal];
    [button addTarget:self action:@selector(GotoWeatherInfoViewAction:) forControlEvents:UIControlEventTouchUpInside];
    
    UIBarButtonItem *leftWeather = [[UIBarButtonItem alloc]initWithCustomView:button];
    
    // navigationbar setup
    self.navigationItem.rightBarButtonItem = self.addBtn;
    self.navigationItem.leftBarButtonItems = @[self.editBtn,leftWeather];
//    self.navigationItem.leftBarButtonItem = self.editBtn;
    
    // toolbar setup
    [self refreshToolBar:NO];

    // title setup
    [self initTitle];
    
    // tableview setup
    
    //CGRect statusBarFrame = [self.navigationController.view.window convertRect:UIApplication.sharedApplication.statusBarFrame toView:self.navigationController.view];
    //CGFloat statusBarHeight = statusBarFrame.size.height;
    
    CGRect tableFrame = bg.frame;
    tableFrame.size.height = [rTracker_resource get_visible_size:self].height;// - ( 2 * statusBarHeight ) ;

#if ADVERSION
    if (![rTracker_resource getPurchased]) {
#if !DISABLE_ADS
        tableFrame.size.height -= self.adSupport.bannerView.frame.size.height;
        DBGLog(@"ad h= %f  tfh= %f ",self.adSupport.bannerView.frame.size.height,tableFrame.size.height);
#endif
    }
#endif

    DBGLog(@"tvf origin x %f y %f size w %f h %f",tableFrame.origin.x,tableFrame.origin.y,tableFrame.size.width,tableFrame.size.height);
    self.tableView = [[UITableView alloc]initWithFrame:tableFrame style:UITableViewStylePlain];
    
    //self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    
    self.tableView.backgroundView = bg;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;

    //UIView *tfv = [[UIView alloc]initWithFrame:CGRectMake(0, 0, 768, 10)];
    //tfv.backgroundColor = [UIColor yellowColor];
    //self.tableView.tableFooterView = tfv;
    
    [self.view addSubview:self.tableView];

    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"9.0")) {
        NSArray <UIApplicationShortcutItem *> *existingShortcutItems = [[UIApplication sharedApplication] shortcutItems];
        if (0 == [existingShortcutItems count] /*|| ([rTracker_resource getSCICount] != [existingShortcutItems count]) */ ) {  // can#'t set more than 4 or prefs messed up
            [self.tlist updateShortcutItems];
        }
    }
    
}

- (trackerList *) tlist {
    if (nil == _tlist) {
        trackerList *tmptlist = [[trackerList alloc] init];
        self.tlist = tmptlist;
        
        if ([self.tlist recoverOrphans]) {     // added 07.viii.13
            [rTracker_resource alert:@"Recovered files" msg:@"One or more tracker files were recovered, please delete if not needed." vc:self];
        }
        [self.tlist loadTopLayoutTable];
    }
    return _tlist;
}

- (void) refreshEditBtn {

/*
	if ([self.tlist.topLayoutNames count] == 0) {
		if (self.navigationItem.backBarButtonItem != nil) {
			self.navigationItem.backBarButtonItem = nil;
		}
	} else {
		if (self.navigationItem.backBarButtonItem == nil) {
			self.navigationItem.backBarButtonItem = self.editBtn;
			//[editBtn release];
		}
	}
*/
	if ([self.tlist.topLayoutNames count] == 0) {
		if (self.navigationItem.leftBarButtonItem != nil) {
			self.navigationItem.leftBarButtonItem = nil;
		}
	} else {
		if (self.navigationItem.leftBarButtonItem == nil) {
			self.navigationItem.leftBarButtonItem = self.editBtn;
			//[editBtn release];
		}
	}
    
}

- (BOOL) samplesNeeded {
    NSString *sql = @"select val from info where name = 'samples_version'";
    int rslt = [self.tlist toQry2Int:sql];
    DBGLog(@"samplesNeeded if %d != %d",SAMPLES_VERSION,rslt);
    return (SAMPLES_VERSION != rslt);
}

- (BOOL) demosNeeded {
    NSString *sql = @"select val from info where name = 'demos_version'";
    int rslt = [self.tlist toQry2Int:sql];
    DBGLog(@"demosNeeded if %d != %d",DEMOS_VERSION,rslt);
#if !RELEASE
    //rslt=0;
    if (0 == rslt) {
        DBGLog(@"forcing demosNeeded");
    }
#endif
    return (DEMOS_VERSION != rslt);
}

- (void) handlePrefs {
    
    NSUserDefaults *sud = [NSUserDefaults standardUserDefaults];
    [sud synchronize];

    BOOL resetPassPref = [sud boolForKey:@"reset_password_pref"];
    BOOL reloadSamplesPref = [sud boolForKey:@"reload_sample_trackers_pref"];
    
    [rTracker_resource setSeparateDateTimePicker:[sud boolForKey:@"separate_date_time_pref"]];
    [rTracker_resource setRtcsvOutput:[sud boolForKey:@"rtcsv_out_pref"]];
    [rTracker_resource setSavePrivate:[sud boolForKey:@"save_priv_pref"]];

    //[rTracker_resource setHideRTimes:[sud boolForKey:@"hide_rtimes_pref"]];
    //[rTracker_resource setSCICount:(NSUInteger)[sud integerForKey:@"shortcut_count_pref"]];
    
    [rTracker_resource setToldAboutSwipe:[sud boolForKey:@"toldAboutSwipe"]];
    [rTracker_resource setToldAboutNotifications:[sud boolForKey:@"toldAboutNotifications"]];
    [rTracker_resource setAcceptLicense:[sud boolForKey:@"acceptLicense"]];
    
    //DBGLog(@"entry prefs-- resetPass: %d  reloadsamples: %d",resetPassPref,reloadSamplesPref);

    if (resetPassPref) [self.privacyObj resetPw];
    
    InstallSamples = NO;
    InstallDemos = NO;
    if (reloadSamplesPref) {
        InstallSamples = YES;
        InstallDemos = YES;
    } else {
        if ([self samplesNeeded]) {
            InstallSamples = YES;
        }
        if ([self demosNeeded]) {
            //[self deleteDemos];
            InstallDemos = YES;
        }
    }
    /*
    if (reloadSamplesPref
        || 
        //(self.initialPrefsLoad && [self samplesNeeded])
        [self samplesNeeded]
        ) { 
        InstallSamples = YES;
    } else {
        InstallSamples = NO;
    }
    
    if (reloadSamplesPref
        ||
        //(self.initialPrefsLoad && [self demosNeeded])
        [self demosNeeded]
        ) {
        InstallDemos = YES;
    } else {
        InstallDemos = NO;
    }
    */
    
    DBGLog(@"InstallSamples %d  InstallDemos %d",InstallSamples,InstallDemos);
    
    if (resetPassPref)
        [sud setBool:NO forKey:@"reset_password_pref"];
    if (reloadSamplesPref)
        [sud setBool:NO forKey:@"reload_sample_trackers_pref"];
    
    self.initialPrefsLoad = NO;
    
    [sud synchronize];
/*
#if DEBUGLOG
    resetPassPref = [sud boolForKey:@"reset_password_pref"];
    reloadSamplesPref = [sud boolForKey:@"reload_sample_trackers_pref"];
    
    DBGLog(@"exit prefs-- resetPass: %d  reloadsamples: %d",resetPassPref,reloadSamplesPref);
#endif
*/
}

- (void) refreshView {
    
    if (0 != OSAtomicTestAndSet(0, &(_refreshLock))) {
        // wasn't 0 before, so we didn't get lock, so leave because refresh already in process
        return;
    }
            
    //DBGLog(@"refreshView");
	[self scrollState];

    [self handlePrefs];
    
    [self loadInputFiles];  // do this here as restarts are infrequent and prv change may enable to read more files
    
    [self countScheduledReminders];
    
}
/*
- (void) jumpMaxPriv {
    if (nil == self.stashedPriv) {
        self.stashedPriv = @([privacyV getPrivacyValue]);
        DBGLog(@"stashed priv %@",self.stashedPriv);
    }

    [self.privacyObj setPrivacyValue:MAXPRIV];  // temporary max privacy level so see all
    DBGLog(@"priv jump!");
}
- (void) restorePriv {
    if (nil == self.stashedPriv) {
        return;
    }
    //if (YES == self.openUrlLock) {
    //    return;
    //}
    DBGLog(@"restore priv to %@",self.stashedPriv);
    [self.privacyObj setPrivacyValue:[self.stashedPriv intValue]];  // return to privacy level
    self.stashedPriv = nil;
    
}
*/

#if ADVERSION
// handle rtPurchasedNotification
- (void) updatePurchased:(NSNotification*)n {
    if (n) {
        [rTracker_resource doQuickAlert:@"Purchase Successful" msg:@"Thank you!" delay:2 vc:self];
    }

    if (nil != _adSupport) {
        if ([self.adSupport.bannerView isDescendantOfView:self.view]) {
            [self.adSupport.bannerView removeFromSuperview];
        }
        self.adSupport = nil;
    }
    UIImageView *bg = [[UIImageView alloc] initWithImage:[UIImage imageNamed:[rTracker_resource getLaunchImageName]]];
    CGRect tableFrame = bg.frame;
    tableFrame.size.height = [rTracker_resource get_visible_size:self].height;// - ( 2 * statusBarHeight ) ;
    [self.tableView setFrame:tableFrame];
    self.tableView.backgroundView = bg;
    [self.tableView setNeedsDisplay];
    //[self.tableView reloadData];
}
#endif

- (void)viewWillAppear:(BOOL)animated {
    
    DBGLog(@"rvc: viewWillAppear privacy= %d", [privacyV getPrivacyValue]);
    //[self loadInputFiles];  // do this here as restarts are infrequent
    //[self refreshView];
    
    //[self restorePriv];
    [privacyV restorePriv];
    //[self refreshViewPart2];
    
    [self.navigationController setToolbarHidden:NO animated:NO];
    
    CGRect f = self.view.frame;
    if (f.size.width != self.tableView.frame.size.width) {
        f.origin.x = 0.0; f.origin.y = 0.0;
        self.tableView.frame = f;
        self.tableView.backgroundView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:[rTracker_resource getLaunchImageName]]];
        /*
         [self.navigationController.toolbar setBackgroundImage: [UIImage imageNamed:[rTracker_resource getLaunchImageName]]
         forToolbarPosition: UIToolbarPositionAny
         barMetrics: UIBarMetricsDefault];
         */
    }
    f = self.tableView.frame;
    f.size.height = [rTracker_resource get_visible_size:self].height;  // fix inaccessible trackers at bottom after rotate from graph view
    self.tableView.frame = f;

#if ADVERSION
    
    if (![rTracker_resource getPurchased]) {
#if !DISABLE_ADS
        [self.adSupport initBannerView:self];
        [self.view addSubview:self.adSupport.bannerView];
#endif
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(updatePurchased:)
                                                     name:rtPurchasedNotification
                                                   object:nil];
    } else if (_adSupport) {
        [self updatePurchased:nil];
    }
    
#endif
    
    [super viewWillAppear:animated];
}

BOOL stashAnimated;

- (void) fixFileProblem:(NSInteger)choice {
    NSString *docsDir = [rTracker_resource ioFilePath:nil access:YES];
    
    NSFileManager *localFileManager=[NSFileManager defaultManager];
    NSDirectoryEnumerator *dirEnum = [localFileManager enumeratorAtPath:docsDir];
    
    NSString *file;
    
    while ((file = [dirEnum nextObject])) {
        if ([[file pathExtension] isEqualToString: @"rtrk_reading"]) {
            NSError *err;
            NSString *target;
            target = [docsDir stringByAppendingPathComponent:file];
            
            if (0 == choice) {   // delete it
                [rTracker_resource deleteFileAtPath:target];
            } else {                  // try again -- rename from .rtrk_reading to .rtrk
                NSString *newTarget;
                newTarget = [target stringByReplacingOccurrencesOfString:@"rtrk_reading" withString:@"rtrk"];
                if ([localFileManager moveItemAtPath:target toPath:newTarget error:&err] != YES) {
                    DBGLog(@"Error on move %@ to %@: %@",target, newTarget, err);
                    //DBGLog(@"Unable to move file: %@", [err localizedDescription]);
                }
            }
        }
    }
    
    [self viewDidAppearRestart];
    
}
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    [self fixFileProblem:buttonIndex];
}

- (void) viewDidAppearRestart {
	[self refreshView];
    //[super viewDidAppear:stashAnimated];
#if ADVERSION
    if (![rTracker_resource getPurchased]) {
#if !DISABLE_ADS

        [self.adSupport layoutAnimated:self tableview:self.tableView animated:NO];
#endif
    }
#endif
   
    [super viewDidAppear:stashAnimated];
}

- (void) doOpenTrackerRejectable:(NSNumber*)nsnTid {
    [self openTracker:[nsnTid intValue] rejectable:YES];
}

- (void) doOpenTracker:(NSNumber*)nsnTid {
    [self openTracker:[nsnTid intValue] rejectable:NO];
}

/*
- (void) doOpenURL:(NSURL*)url {
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    //if (url != nil && [url isFileURL]) {
    
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    int tid = [self handleOpenFileURL:url tname:nil];
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    
    if (0 != tid) {
        // get to root view controller, else get last view on stack
        //[rootController openTracker:tid rejectable:YES];
        [self performSelectorOnMainThread:@selector(doOpenTracker:) withObject:[NSNumber numberWithInt:tid] waitUntilDone:YES];
    }
    //}
    
    [self finishRvcActivityIndicator];
    //UIViewController *topController = [self.navigationController.viewControllers lastObject];
    //[rTracker_resource startActivityIndicator:topController.view navItem:nil disable:NO];
    
    self.openUrlLock=NO;
    self.inputURL=nil;
    [pool drain];
}


- (void) openInputURL {
    
    [self startRvcActivityIndicator];
    
    //UIViewController *topController = [self.navigationController.viewControllers lastObject];
    //[rTracker_resource startActivityIndicator:topController.view navItem:nil disable:NO];
    
    [NSThread detachNewThreadSelector:@selector(doOpenURL:) toTarget:self withObject:self.inputURL];
    //[self doOpenURL:url];
}
*/

- (void) doRejectableTracker {
    //DBGLog(@"stashedTIDs= %@",self.stashedTIDs);
    NSNumber *nsntid = [self.stashedTIDs lastObject];
    [self performSelectorOnMainThread:@selector(doOpenTrackerRejectable:) withObject:nsntid waitUntilDone:YES];
    [self.stashedTIDs removeLastObject];
}
/*
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    
    CGRect f = self.view.frame;
    f.origin.x = 0.0; f.origin.y = 0.0;
    self.tableView.frame = f;
    self.tableView.backgroundView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:[rTracker_resource getLaunchImageName]]];
    DBGLog(@"rotated...");
    
}
*/
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    //if ( self.isViewLoaded && self.view.window ) {
    
    // viewController is visible
    //CGRect f = self.view.frame;
    CGRect f;
    f.origin.x = 0.0; f.origin.y = 0.0;
    f.size = size;
    self.tableView.frame = f;
    self.tableView.backgroundView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:[rTracker_resource getLaunchImageName]]];
    DBGLog(@"rotated...");
    //}
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

}


- (void) viewDidAppear:(BOOL)animated {
    
    //DBGLog(@"rvc: viewDidAppear privacy= %d", [privacyV getPrivacyValue]);
    /*
     if (self.inputURL && !self.openUrlLock) {
     self.openUrlLock = YES;
     [self openInputURL];
     } else
     */
    
    if (! self.readingFile) {
        if (0 < [self.stashedTIDs count]) {
            [self doRejectableTracker];
        } else {
            NSString *docsDir = [rTracker_resource ioFilePath:nil access:YES];
            NSFileManager *localFileManager=[NSFileManager defaultManager];
            NSDirectoryEnumerator *dirEnum = [localFileManager enumeratorAtPath:docsDir];
            
            NSString *file;
            
            while ((file = [dirEnum nextObject])) {
                if ([[file pathExtension] isEqualToString: @"rtrk_reading"]) {
                    NSString *fname = [file lastPathComponent];
                    NSString *rtrkName = [fname stringByDeletingPathExtension];
                    NSString *title = @"Problem reading .rtrk file?";
                    NSString *msg = [ NSString stringWithFormat:@"There was a problem while loading the %@ rtrk file",rtrkName ];
                    NSString *btn0 = @"Delete it";
                    NSString *btn1 = @"Try again";
                    if (SYSTEM_VERSION_LESS_THAN(@"8.0")) {
                        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                                        message:msg
                                                                       delegate:self
                                                              cancelButtonTitle:btn0
                                                              otherButtonTitles:btn1,nil];
                        [alert show];
                    } else {
                        UIAlertController* alert = [UIAlertController alertControllerWithTitle:title
                                                                                       message:msg
                                                                                preferredStyle:UIAlertControllerStyleAlert];
                        
                        UIAlertAction* deleteAction = [UIAlertAction actionWithTitle:btn0 style:UIAlertActionStyleDefault
                                                                             handler:^(UIAlertAction * action) { [self fixFileProblem:0]; }];
                        UIAlertAction* retryAction = [UIAlertAction actionWithTitle:btn1 style:UIAlertActionStyleDefault
                                                                            handler:^(UIAlertAction * action) { [self fixFileProblem:1]; }];
                        
                        [alert addAction:deleteAction];
                        [alert addAction:retryAction];
                        
                        [self presentViewController:alert animated:YES completion:nil];
                        
                    }
                }
            }
        }
    } else {
        //if (self.readingFile) {
        [UIApplication sharedApplication].idleTimerDisabled = YES;
    }
    stashAnimated = animated;
    [self viewDidAppearRestart];
    
    // [super viewDidApeear] called in [self viewDidAppearRestart]
}


- (void)viewWillDisappear:(BOOL)animated {
    DBGLog(@"rvc viewWillDisappear");

#if ADVERSION
    //unregister for purchase notices
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:rtPurchasedNotification
                                                    object:nil];
#endif
    
    [super viewWillDisappear:animated];
}


/*
#if ADVERSION
- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    //[self.adSupport stopTimer];
}
#endif
*/

- (void)didReceiveMemoryWarning {
	// Releases the view if it doesn't have a superview.
	
	DBGWarn(@"rvc didReceiveMemoryWarning");
	// Release any cached data, images, etc that aren't in use.

    [super didReceiveMemoryWarning];


}
/*
- (void)viewDidUnload {
	// Release anything that can be recreated in viewDidLoad or on demand.
	// e.g. self.myOutlet = nil;
	
	//DBGLog(@"rvc viewDidUnload");

	self.title = nil;
	self.navigationItem.rightBarButtonItem = nil;
	self.navigationItem.leftBarButtonItem = nil;
	[self setToolbarItems:nil
				 animated:NO];
	
	self.tlist = nil;
	
	//DBGLog(@"pb rc= %d  mgb rc= %d", [self.privateBtn retainCount], [self.multiGraphBtn retainCount]);
    
    [super viewDidUnload];
	
}
*/

- (void) startRvcActivityIndicator {
    //[rTracker_resource startActivityIndicator:self.view navItem:nil disable:NO];
    [self.tableView scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:YES];  // ScrollToTop so can see bars
    //CGRect navframe = [[self.navigationController navigationBar] frame];
    //[rTracker_resource startProgressBar:self.view navItem:self.navigationItem disable:YES  yloc:(navframe.size.height + navframe.origin.y)];
    [rTracker_resource startProgressBar:self.view navItem:self.navigationItem disable:YES  yloc:0.0f];
}
- (void) finishRvcActivityIndicator {
    //[rTracker_resource finishActivityIndicator:self.view navItem:nil disable:NO];
    [rTracker_resource finishProgressBar:self.view navItem:self.navigationItem disable:YES];
}


#pragma mark -
#pragma mark button accessor getters

/*
 - (UIBarButtonItem *) payBtn {
	if (payBtn == nil) {
		payBtn = [[UIBarButtonItem alloc]
					  initWithTitle:@"$"
					  style:UIBarButtonItemStylePlain
					  target:self
					  action:@selector(btnPay)];
	}
	return payBtn;
}
*/

- (void) privBtnSetImg:(UIButton*)pbtn noshow:(BOOL)noshow {
    //BOOL shwng = (self.privacyObj.showing == PVNOSHOW); 
    BOOL minprv = ( [privacyV getPrivacyValue] > MINPRIV );
    
    NSString *btnImg = ( kIS_LESS_THAN_IOS7 ?
                        ( noshow ? ( minprv ? @"shadeview-button.png" : @"closedview-button.png" )
                         : ( minprv ? @"shadeview-button-blue.png" : @"closedview-button-blue.png" ) )
                        :
                        ( noshow ? ( minprv ? @"shadeview-button-7.png" : @"closedview-button-7.png" )
                         : ( minprv ? @"shadeview-button-blue-7.png" : @"closedview-button-blue-7.png" ) )
                        )
                        ;
    dispatch_async(dispatch_get_main_queue(), ^(void){
        [pbtn setImage:[UIImage imageNamed:btnImg] forState:UIControlStateNormal];
    });
}

- (UIBarButtonItem *) privateBtn {
    //
	if (_privateBtn == nil) {
        // /*
        UIButton *pbtn = [[UIButton alloc] init];
        [pbtn setImage:[UIImage imageNamed:(kIS_LESS_THAN_IOS7 ? @"closedview-button.png" : @"closedview-button-7.png")]
              forState:UIControlStateNormal];
        pbtn.frame = CGRectMake(0, 0, ( pbtn.currentImage.size.width * 1.5 ), pbtn.currentImage.size.height);
        [pbtn addTarget:self action:@selector(btnPrivate) forControlEvents:UIControlEventTouchUpInside];
        _privateBtn = [[UIBarButtonItem alloc]
                      initWithCustomView:pbtn];
        [self privBtnSetImg:(UIButton*)_privateBtn.customView noshow:YES];
	} else {
        BOOL noshow=YES;
        if (_privacyObj)  // don't instantiate unless needed
            noshow = (PVNOSHOW == self.privacyObj.showing); 
        if ((! noshow) 
            && (PWKNOWPASS == self.privacyObj.pwState)) {
            //DBGLog(@"unlock btn");
            [(UIButton *)_privateBtn.customView
             setImage:[UIImage imageNamed:(kIS_LESS_THAN_IOS7 ? @"fullview-button-blue.png" : @"fullview-button-blue-7.png")]
             forState:UIControlStateNormal];
        } else {
            //DBGLog(@"lock btn");
            [self privBtnSetImg:(UIButton *)_privateBtn.customView noshow:noshow];
        }
    }


	return _privateBtn;
}

- (UIBarButtonItem *) helpBtn {
	if (_helpBtn == nil) {
		_helpBtn = [[UIBarButtonItem alloc]
                      initWithTitle:@"Help"
                      style:UIBarButtonItemStylePlain
                      target:self
                      action:@selector(btnHelp)];
	} 
	return _helpBtn;
}


- (UIBarButtonItem *) addBtn {
	if (_addBtn == nil) {
        _addBtn = [[UIBarButtonItem alloc]
                initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                  //initWithTitle:@"New tracker"
                  //style:UIBarButtonItemStylePlain 
                 target:self
                 action:@selector(btnAddTracker)];

        [_addBtn setStyle:UIBarButtonItemStyleDone];
        
	} 
	return _addBtn;
}

- (UIBarButtonItem *) editBtn {
	if (_editBtn == nil) {
        _editBtn = [[UIBarButtonItem alloc]
                   initWithBarButtonSystemItem:UIBarButtonSystemItemEdit
                   //initWithTitle:@"Edit trackers"
                   //style:UIBarButtonItemStylePlain 
                   target:self
                   action:@selector(btnEdit)];
    
        [_editBtn setStyle:UIBarButtonItemStylePlain];
	}
	return _editBtn;
}


- (UIBarButtonItem *) flexibleSpaceButtonItem {
	if (_flexibleSpaceButtonItem == nil) {
		_flexibleSpaceButtonItem = [[UIBarButtonItem alloc]
                initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace 
                target:nil action:nil];
	} 
	return _flexibleSpaceButtonItem;
}

/*
 - (UIBarButtonItem *) multiGraphBtn {
	if (multiGraphBtn == nil) {
		multiGraphBtn = [[UIBarButtonItem alloc]
					  initWithTitle:@"Multi-Graph"
					  style:UIBarButtonItemStylePlain
					  target:self
					  action:@selector(btnMultiGraph)];
	}
	return multiGraphBtn;
}
*/

#pragma mark -

- (privacyV*) privacyObj {
	if (_privacyObj == nil) {
		_privacyObj = [[privacyV alloc] initWithParentView:self.view];
        _privacyObj.parent = self;
	}
	_privacyObj.tob = (id) self.tlist;  // not set at init
	return _privacyObj;
}

- (NSMutableArray*) stashedTIDs {
    if (_stashedTIDs == nil) {
        _stashedTIDs = [[NSMutableArray alloc] init];
    }
    return  _stashedTIDs;
}

- (void) countScheduledReminders {
    UIApplication *app = [UIApplication sharedApplication];
    NSArray *eventArray = [app scheduledLocalNotifications];
    [self.scheduledReminderCounts removeAllObjects];
    for (int i=0; i<[eventArray count]; i++)
    {
        UILocalNotification* oneEvent = eventArray[i];
        NSDictionary *userInfoCurrent = oneEvent.userInfo;
        NSNumber *tid =userInfoCurrent[@"tid"];
        int c = [(self.scheduledReminderCounts)[tid] intValue];
        c++;
        (self.scheduledReminderCounts)[tid] = @(c);
    }
    
}

- (NSMutableDictionary*) scheduledReminderCounts {
    if (nil == _scheduledReminderCounts) {
        _scheduledReminderCounts = [[NSMutableDictionary alloc]init];
    }
    return _scheduledReminderCounts;
}

#pragma mark -
#pragma mark button action methods

- (void) btnAddTracker {
    if (PVNOSHOW != self.privacyObj.showing) {
        return;
    }
#if ADVERSION
    if (![rTracker_resource getPurchased]) {
        if (ADVER_TRACKER_LIM <= [self.tlist.topLayoutIDs count]) {
            //[rTracker_resource buy_rTrackerAlert];
            [rTracker_resource replaceRtrackerA:self];
            return;
        }
    }
#endif
	addTrackerController *atc = [[addTrackerController alloc] initWithNibName:@"addTrackerController" bundle:nil ];
	atc.tlist = self.tlist;
	[self.navigationController pushViewController:atc animated:YES];
    //[rTracker_resource myNavPushTransition:self.navigationController vc:atc animOpt:UIViewAnimationOptionTransitionCurlUp];
    
}

- (IBAction)btnEdit {
    
    if (PVNOSHOW != self.privacyObj.showing) {
        return;
    }
    configTlistController *ctlc;
    //if(kIS_LESS_THAN_IOS7) {
    //    ctlc = [[configTlistController alloc] initWithNibName:@"configTlistController" bundle:nil ];
    //} else {
        ctlc = [[configTlistController alloc] initWithNibName:@"configTlistController" bundle:nil ];
    //}
	ctlc.tlist = self.tlist;
	[self.navigationController pushViewController:ctlc animated:YES];
    
    //[rTracker_resource myNavPushTransition:self.navigationController vc:ctlc animOpt:UIViewAnimationOptionTransitionFlipFromLeft];
    
}
	
- (void)btnMultiGraph {
	DBGLog(@"btnMultiGraph was pressed!");
}

- (void)btnPrivate {
    [self.tableView scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:YES];  // ScrollToTop
	[self.privacyObj togglePrivacySetter ];
    /*
	if (PVNOSHOW != self.privacyObj.showing) {
		self.privateBtn.title = @"dismiss";
	} else {
		self.privateBtn.title = @"private";
		[self refreshView];
	}
     */
    if (PVNOSHOW == self.privacyObj.showing) 
        [self refreshView];
}

- (void) btnHelp {
#if ADVERSION
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/summit1206/rTracker--889"]];
#else
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/summit1206/rTracker--889"]];
#endif
}

- (void)btnPay {
	DBGLog(@"btnPay was pressed!");
	
}

#pragma mark -
#pragma mark Table view methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

// Customize the number of rows in the table view.
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [self.tlist.topLayoutNames count];
}

- (NSInteger) pendingNotificationCount {
    NSInteger erc=0,src=0;
    for (NSNumber *nsn in self.tlist.topLayoutReminderCount) {
        erc += [nsn integerValue];
    }
    for (NSNumber *tid in self.scheduledReminderCounts) {
        src += [(self.scheduledReminderCounts)[tid] integerValue];
    }
    
    return (erc > src ? erc-src : 0);
}

// Customize the appearance of table view cells.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    //DBGLog(@"rvc table cell at index %d label %@",[indexPath row],[tlist.topLayoutNames objectAtIndex:[indexPath row]]);
	
    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];

        //UIImageView *bg = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"bkgnd-cell1-320-56.png"]]; // note needs to be @2x.png for retina
        //[cell setBackgroundView:bg];
        //[bg release];

        cell.backgroundColor = [UIColor clearColor];
        //cell.backgroundColor = [UIColor greenColor];
        
        //UIView* separatorLineView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 1)];
        //separatorLineView.backgroundColor =[UIColor redColor];
        //[cell.contentView addSubview:separatorLineView];

        //cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    
	// Configure the cell.
	NSUInteger row = [indexPath row];
    NSNumber *tid = (self.tlist.topLayoutIDs)[row];
    NSMutableAttributedString *cellLabel = [[NSMutableAttributedString alloc] init];

    int erc = [(self.tlist.topLayoutReminderCount)[row] intValue];
    int src = [(self.scheduledReminderCounts)[tid] intValue];
    //DBGLog(@"src: %d  erc:  %d",src,erc);
    //NSString *formatString = @"%@";
    //UIColor *bg = [UIColor clearColor];
    if (erc != src) {
        //formatString = @"> %@";
        //bg = [UIColor redColor];
        [cellLabel appendAttributedString:
         [[NSAttributedString alloc] initWithString:@"➜ " attributes:@{NSForegroundColorAttributeName: [UIColor redColor],
                                                                       NSFontAttributeName: [UIFont boldSystemFontOfSize:[UIFont labelFontSize]]} ]];
        
    }
    //DBGLog(@"erc= %d  src= %d",erc,src);
    [cellLabel appendAttributedString:[[NSAttributedString alloc]initWithString:(self.tlist.topLayoutNames)[row]]];
    cell.textLabel.attributedText = cellLabel;
    
	//cell.textLabel.text = [NSString stringWithFormat:formatString,(self.tlist.topLayoutNames)[row]];  // gross but simplest offset option
    //cell.textLabel.backgroundColor = bg;
    //cell.textLabel.backgroundColor = [UIColor clearColor];
    /*
     cell.textLabel.textColor = [UIColor blackColor];
    cell.textLabel.backgroundColor = [UIColor clearColor];
    cell.backgroundColor = [UIColor clearColor];
    [cell.contentView addSubview:[[UIView alloc]init]];
    */
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *tn;
    NSUInteger row = [indexPath row];
    if (NSNotFound != row) {
        tn = (self.tlist.topLayoutNames)[row];
    } else {
        tn = @"Sample";
    }
    CGSize tns = [tn sizeWithAttributes:@{NSFontAttributeName:PrefBodyFont}];
    return tns.height + (2*MARGIN);
}

- (BOOL) exceedsPrivacy:(NSInteger)tid {
    return ([privacyV getPrivacyValue] < [self.tlist getPrivFromLoadedTID:tid]);
}
- (void)openTracker:(NSInteger)tid rejectable:(BOOL)rejectable {
    //if (rejectable) {
    //    [self jumpMaxPriv];
    //}
    
    if ([self exceedsPrivacy:tid]) {
        return;
    }
    
    UIViewController *topController = [self.navigationController.viewControllers lastObject];
    SEL rtSelector = NSSelectorFromString(@"rejectTracker");
    
    if ( [topController respondsToSelector:rtSelector] ) {  // top controller is already useTrackerController, is it this tracker?
        if (tid == ((useTrackerController*)topController).tracker.toid) {
            return;
        }
    }
    
    trackerObj *to = [[trackerObj alloc] init:tid];
	[to describe];

	//useTrackerController *utc = [[useTrackerController alloc] initWithNibName:@"useTrackerController" bundle:nil ];
	useTrackerController *utc = [[useTrackerController alloc] init];
    utc.tracker = to;
    utc.rejectable = rejectable;
    utc.tlist = self.tlist;  // required so reject can fix topLevel list
    utc.saveFrame = self.view.frame; // self.tableView.frame; //  view.frame;
    utc.rvcTitle = self.title;
#if ADVERSION
#if !DISABLE_ADS
    if (![rTracker_resource getPurchased]) {
        utc.adSupport = self.adSupport;
    } else {
        utc.adSupport = nil;
    }
#endif
#endif
    
    //if (rejectable) {
    //    [self.navigationController pushViewController:utc animated:NO];
    //} else {
        [self.navigationController pushViewController:utc animated:YES];
    //}
    //[self myNavTransition:utc animOpt:UIViewAnimationOptionTransitionFlipFromLeft];
    
	
}

// Override to support row selection in the table view.
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {

    if (PVNOSHOW != self.privacyObj.showing) {
        return;
    }
    
	//NSUInteger row = [indexPath row];
	//DBGLog(@"selected row %d : %@", row, [self.tlist.topLayoutNames objectAtIndex:row]);
    [tableView cellForRowAtIndexPath:indexPath].selected=NO;
    [self openTracker:[self.tlist getTIDfromIndex:[indexPath row]] rejectable:NO];
	
}

@end

