#import "../playback/WinePlayback.h"
static void check(BOOL ok, const char *text) { NSCAssert(ok,@"%s",text); printf("PASS %s\n",text); }
static NSTask *sleepTask(void) { NSTask *t=[NSTask new];t.executableURL=[NSURL fileURLWithPath:@"/bin/sleep"];t.arguments=@[@"60"];check([t launchAndReturnError:nil],"fixture process starts");return t; }
@interface LifecyclePlayer : LWWinePlayback
@property NSUInteger stopCalls;
@property NSUInteger controlCalls;
@property BOOL sawQuiescing;
@property BOOL rendererGoneBeforePrefixStop;
@property(copy) NSString *testUUID;
@end
@implementation LifecyclePlayer
- (BOOL)stopPrefix:(NSString *)prefix runtime:(NSString *)runtime directory:(NSString *)directory error:(NSError **)error {
 self.stopCalls++;
 NSDictionary *session=self.sessions[self.testUUID];self.sawQuiescing=[session[@"stopping"] boolValue];
 self.rendererGoneBeforePrefixStop=![(NSTask *)session[@"task"] isRunning];
 [self tick]; // Reentrant timer while the stop wait is servicing its run loop.
 return YES;
}
- (void)requestWindowControl:(NSString *)uuid session:(NSMutableDictionary *)session paused:(BOOL)paused {self.controlCalls++;}
@end
int main() { @autoreleasepool {
 NSTask *fast=[NSTask new];fast.executableURL=[NSURL fileURLWithPath:@"/usr/bin/true"];check([fast launchAndReturnError:nil],"fast task starts");check(LWWaitForWineTask(fast,1),"ordinary child exit succeeds");
 NSTask *slow=sleepTask();NSDate *began=NSDate.date;check(!LWWaitForWineTask(slow,.03),"blocked child wait times out");check(-began.timeIntervalSinceNow<1,"timeout is bounded");check(LWWaitForWineTask(slow,1),"timed-out owned child is reaped");
 // Model a Wine helper that ignores SIGTERM. A pipe handshake ensures the
 // signal disposition is installed before the supervisor attempts cleanup.
 NSTask *stubborn=[NSTask new];stubborn.executableURL=[NSURL fileURLWithPath:@"/bin/sh"];
 stubborn.arguments=@[@"-c",@"trap '' TERM; printf x; exec /bin/sleep 60"];
 NSPipe *ready=[NSPipe pipe];stubborn.standardOutput=ready;
 check([stubborn launchAndReturnError:nil],"stubborn control helper starts");
 check([ready.fileHandleForReading readDataOfLength:1].length==1,"helper ignores SIGTERM before timeout");
 began=NSDate.date;
 check(!LWWaitForWineTask(stubborn,0),"expired control helper uses bounded cancellation");
 check(-began.timeIntervalSinceNow<1,"ignored SIGTERM cannot extend cleanup indefinitely");
 check(LWWaitForWineTask(stubborn,1) && !stubborn.running,"stubborn owned helper is killed and reaped");
 [ready.fileHandleForReading closeFile];
 NSScreen *screen=NSScreen.mainScreen;check(screen!=nil,"screen available for display identity fixture");
 CGDirectDisplayID display=[screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];CFUUIDRef value=CGDisplayCreateUUIDFromDisplayID(display);NSString *uuid=CFBridgingRelease(CFUUIDCreateString(NULL,value));CFRelease(value);
 NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];NSFileManager *fm=NSFileManager.defaultManager;
 NSArray *files=@[@"WinePlayer.app/Contents/MacOS/wine",@"WinePlayer.app/Contents/MacOS/ntdll.so",@"wine/bin/wineserver",@"wine/lib/wine/x86_64-windows/winegstreamer.dll",@"wine/lib/wine/x86_64-unix/winegstreamer.so",@"wine/lib/wine/x86_64-windows/mfmediaengine.dll",@"desktop_window_bridge.dylib",@"window-playback-control.exe",@"engine/wallpaper64.exe",@"runtime.json",@"project.json",@"window.json"];
 for(NSString *name in files){NSString *p=[root stringByAppendingPathComponent:name];[fm createDirectoryAtPath:p.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];[NSData.data writeToFile:p atomically:YES];}
 [[NSJSONSerialization dataWithJSONObject:@{@"rendererReady":@YES,@"firstFramePresented":@YES,@"rendererSizeMismatch":@NO} options:0 error:nil] writeToFile:[root stringByAppendingPathComponent:@"window.json"] atomically:YES];
 setenv("LIVEWALLPAPER_WINE_RUNTIME",root.fileSystemRepresentation,1);
 NSString *canonical=[root stringByResolvingSymlinksInPath];char resolved[PATH_MAX];check(realpath(root.fileSystemRepresentation,resolved)!=NULL,"runtime identity resolves");NSString *runtime=[NSString stringWithUTF8String:resolved];
 NSString *project=[root stringByAppendingPathComponent:@"project.json"];
 NSTask *renderer=sleepTask();LifecyclePlayer *player=[LifecyclePlayer new];player.testUUID=uuid;
 player.sessions[uuid]=@{@"task":renderer,@"project":project.stringByResolvingSymlinksInPath.stringByStandardizingPath,@"runtime":runtime,@"prefix":root,@"directory":root,@"status":[root stringByAppendingPathComponent:@"window.json"],@"started":NSDate.date,@"ready":@YES,@"controlApplied":@NO};
 NSError *error=nil;
 check([player start:project screen:screen error:&error] && !error,"same wallpaper reselect succeeds during startup");
 check(player.stopCalls==0 && player.sessions[uuid][@"task"]==renderer && renderer.running,"reselect preserves renderer and does not stop Wine");
 check([player stopDisplay:uuid],"explicit stop completes");
 check(player.sawQuiescing && player.rendererGoneBeforePrefixStop,"monitor quiesces and renderer exits before server flush");
 check(player.controlCalls==0,"reentrant monitor cannot restart helpers during cleanup");
 check(!player.sessions.count && !renderer.running,"stop releases only completed owned session");
 [fm removeItemAtPath:root error:nil];puts("Lifecycle tests passed; no Wine/player/audio launched");
 }return 0;}
