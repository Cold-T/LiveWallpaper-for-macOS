#import "../playback/WinePlayback.h"

@interface WakePlayer : LWWinePlayback
@property NSUInteger restarts;
@property NSUInteger stops;
@property NSUInteger controls;
@property BOOL displayAvailable;
@end
@implementation WakePlayer
- (NSScreen *)screenForUUID:(NSString *)uuid { return self.displayAvailable ? (NSScreen *)@"screen fixture" : nil; }
- (BOOL)stopDisplay:(NSString *)uuid { self.stops++; [self.sessions removeObjectForKey:uuid]; return YES; }
- (BOOL)start:(NSString *)project screen:(NSScreen *)screen error:(NSError **)error {
  NSCAssert([project isEqual:@"/original/project.json"], @"Restore the original wallpaper");
  self.restarts++;
  self.sessions[@"display"] = @{@"started":NSDate.date, @"project":project, @"status":@"/missing", @"directory":NSTemporaryDirectory()};
  return YES;
}
- (void)requestWindowControl:(NSString *)uuid session:(NSMutableDictionary *)session paused:(BOOL)pause {
  self.controls++;
  session[@"paused"] = @(pause); session[@"controlApplied"] = @YES;
}
@end

int main() { @autoreleasepool {
  WakePlayer *player = [WakePlayer new]; [player.monitor invalidate]; player.displayAvailable = YES;
  __block NSUInteger errors = 0;
  id observer = [NSNotificationCenter.defaultCenter addObserverForName:@"LWWinePlaybackError" object:nil queue:nil usingBlock:^(NSNotification *note) { errors++; }];
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *status = [dir stringByAppendingPathComponent:@"window.json"];
  [@"{\"rendererReady\":1,\"firstFramePresented\":1}" writeToFile:status atomically:YES encoding:NSUTF8StringEncoding error:nil];
  [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate:[NSDate dateWithTimeIntervalSinceNow:-3600]} ofItemAtPath:status error:nil];
  NSTask *task = [NSTask new]; task.executableURL = [NSURL fileURLWithPath:@"/bin/sleep"]; task.arguments = @[@"120"]; [task launchAndReturnError:nil];
  NSDictionary *(^fixture)(void) = ^{ return @{@"task":task, @"project":@"/original/project.json", @"started":[NSDate dateWithTimeIntervalSinceNow:-7200], @"ready":@YES, @"playbackStarted":@YES, @"status":status, @"directory":dir}; };
  player.sessions[@"display"] = fixture();
  [player sleep:nil]; [player tick];
  NSCAssert(player.sessions.count == 1 && !player.stops && !errors, @"Sleep must not expire stale heartbeat");
  [player wake:nil]; [player tick];
  NSCAssert(!player.stops && !errors && player.sessions[@"display"][@"resumeDeadline"], @"Wake waits for a fresh heartbeat");
  NSMutableDictionary *session = [player.sessions[@"display"] mutableCopy];
  session[@"resumeDeadline"] = [NSDate dateWithTimeIntervalSinceNow:-1]; player.sessions[@"display"] = session;
  [player tick];
  NSCAssert(player.restarts == 1 && player.stops == 1 && !errors, @"Stalled renderer automatically restarts after wake");
  [player tick]; NSCAssert(player.restarts == 1, @"Recovery must not repeatedly restart a fresh launch");
  // A fresh renderer is resumed in place, and failures interrupted by sleep
  // do not poison its control retry budget.
  [@"{\"rendererReady\":1,\"firstFramePresented\":1}" writeToFile:status atomically:YES encoding:NSUTF8StringEncoding error:nil];
  player.sessions[@"display"] = fixture();
  [player sleep:nil]; [player wake:nil];
  session = [player.sessions[@"display"] mutableCopy]; session[@"resumeDeadline"] = [NSDate dateWithTimeIntervalSinceNow:-1]; player.sessions[@"display"] = session;
  [player tick]; NSCAssert(player.restarts == 1 && !player.sessions[@"display"][@"resumeDeadline"] && !errors, @"Healthy renderer survives wake without restart");
  // User Stop while recovery is pending must cancel automatic restoration.
  [player sleep:nil]; [player wake:nil]; [player stopAll]; [player tick];
  NSCAssert(!player.sessions.count && player.restarts == 1, @"Explicit stop cancels wake recovery");
  // Missing displays retain their original session; no fallback to main screen.
  player.sessions[@"display"] = fixture(); [player wake:nil]; player.displayAvailable = NO;
  [NSFileManager.defaultManager removeItemAtPath:status error:nil];
  session = [player.sessions[@"display"] mutableCopy]; session[@"resumeDeadline"] = [NSDate dateWithTimeIntervalSinceNow:-1]; player.sessions[@"display"] = session;
  [player tick]; NSCAssert(player.sessions.count == 1 && player.restarts == 1 && !errors, @"Wait for the original display to reconnect");
  player.displayAvailable = YES;
  session = [player.sessions[@"display"] mutableCopy]; session[@"resumeDeadline"] = [NSDate dateWithTimeIntervalSinceNow:-1]; player.sessions[@"display"] = session;
  [player tick]; NSCAssert(player.restarts == 2 && !errors, @"Restore wallpaper when original display returns");
  [player stopAll]; LWCancelWineTask(task); LWWaitForWineTask(task, 1);
  [NSNotificationCenter.defaultCenter removeObserver:observer];
  [NSFileManager.defaultManager removeItemAtPath:dir error:nil];
  puts("PASS sleep, wake grace, stalled recovery, healthy resume, stop cancellation, display reconnect");
} return 0; }
