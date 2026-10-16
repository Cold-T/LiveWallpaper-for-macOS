#import "../playback/WinePlayback.h"
static void check(BOOL ok, NSString *name) { NSCAssert(ok,@"%@",name); printf("PASS %s\n",name.UTF8String); }
int main() { @autoreleasepool {
 NSMutableDictionary *session=[@{@"started":[NSDate dateWithTimeIntervalSinceNow:-10],@"ready":@NO,@"playbackStarted":@NO} mutableCopy];
 check(LWControlStartupGrace(session),@"initial startup within deadline");
 for(NSUInteger i=0;i<20;++i) check(!LWRecordControlFailure(session),@"startup failure has no early modal");
 check([session[@"startupControlFailures"] unsignedIntegerValue]==20 && !session[@"controlFailures"],@"startup failures isolated from playback streak");
 LWAbsorbRendererStatus(session,@{@"rendererReady":@YES,@"firstFramePresented":@NO},YES);
 check([session[@"ready"] boolValue] && ![session[@"playbackStarted"] boolValue],@"surface permits control before first presentation");
 LWAbsorbRendererStatus(session,@{@"firstFramePresented":@YES},NO);
 check(![session[@"playbackStarted"] boolValue],@"stale presentation status ignored");
 session[@"started"]=[NSDate dateWithTimeIntervalSinceNow:-91];
 check(!LWControlStartupGrace(session),@"startup grace bounded by90seconds");
 LWAbsorbRendererStatus(session,@{@"firstFramePresented":@YES},YES);
 check([session[@"playbackStarted"] boolValue] && !LWControlStartupGrace(session),@"fresh first frame exits startup state");
 check(!LWRecordControlFailure(session) && !LWRecordControlFailure(session) && LWRecordControlFailure(session),@"post-start third consecutive failure reports");
 NSString *dir=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];NSString *log=[dir stringByAppendingPathComponent:@"control.log"];
 LWAppendControlLog(log,@"[LWControl] action=identify start\n");LWAppendControlLog(log,@"{\"windowsPID\":32}\n[LWControl] action=identify reason=1 status=0 accepted=1 startup=1\n");
 NSString *text=[NSString stringWithContentsOfFile:log encoding:NSUTF8StringEncoding error:nil];check([text containsString:@"action=identify start"] && [text containsString:@"{\"windowsPID\":32}"] && [text containsString:@"status=0"],@"append summary preserves prior action and JSON output");[NSFileManager.defaultManager removeItemAtPath:dir error:nil];
 CFStringRef mode=CFSTR("LWFoundationTrackingMode");CFRunLoopAddCommonMode(CFRunLoopGetMain(),mode);
 __block BOOL fired=NO;NSTimer *timer=LWPlaybackMonitorTimer(^(NSTimer *t){fired=YES;});
 CFRunLoopRunInMode(mode,2.25,false);[timer invalidate];
 check(fired,@"actual production monitor fires in common tracking mode");
 puts("Startup control Foundation policy tests passed; no Wine/GUI/device execution");
 }return 0; }
