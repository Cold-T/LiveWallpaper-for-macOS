#import <AppKit/AppKit.h>
#import "../playback/WinePlayback.h"

static void Pump(NSTimeInterval seconds) {
  NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
  while (until.timeIntervalSinceNow > 0)
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:MIN(.1, until.timeIntervalSinceNow)]];
}

// Runtime integration probe, not a visual comparison. Uses the production
// supervisor and the caller's explicitly isolated runtime/state environment.
int main(int argc, const char **argv) { @autoreleasepool {
  if (argc != 4) return 2;
  NSString *project = [NSString stringWithUTF8String:argv[1]];
  NSString *output = [NSString stringWithUTF8String:argv[2]];
  NSTimeInterval hold = MAX(1, atof(argv[3]));
  [NSApplication sharedApplication];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
  NSFileManager *fm = NSFileManager.defaultManager;
  [fm createDirectoryAtPath:output withIntermediateDirectories:YES attributes:nil error:nil];
  LWWinePlayback *player = [LWWinePlayback new];
  __block NSString *reportedError = nil;
  id observer = [NSNotificationCenter.defaultCenter addObserverForName:@"LWWinePlaybackError" object:nil queue:nil usingBlock:^(NSNotification *note) {
    reportedError = [note.object description];
  }];
  NSError *error = nil;
  NSDate *started = NSDate.date;
  BOOL launched = [player start:project screen:NSScreen.mainScreen error:&error];
  NSDictionary *session = player.sessions.allValues.firstObject;
  NSString *statusPath = session[@"status"];
  NSDate *ready = nil;
  NSDictionary *status = nil;
  BOOL pauseSent = NO, resumeSent = NO;
  BOOL initiallyLocked = player.locked;
  NSMutableArray *samples = [NSMutableArray array];
  NSTimeInterval lastSample = -1;
  if (launched) {
    while (-started.timeIntervalSinceNow < 100 && player.sessions.count && !reportedError) {
      Pump(.25);
      NSData *data = statusPath ? [NSData dataWithContentsOfFile:statusPath] : nil;
      status = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
      NSDate *modified = statusPath ? [fm attributesOfItemAtPath:statusPath error:nil][NSFileModificationDate] : nil;
      BOOL fresh = modified && -modified.timeIntervalSinceNow < 4 && [status[@"pid"] intValue] > 0 && !status[@"error"];
      if (!ready && fresh) ready = NSDate.date;
      NSTimeInterval sinceStart = -started.timeIntervalSinceNow;
      if (sinceStart - lastSample >= .5) {
        NSDictionary *current = player.sessions.allValues.firstObject;
        [samples addObject:@{@"seconds":@(sinceStart), @"paused":current[@"paused"] ?: @NO,
          @"locked":@(player.locked), @"frames":status[@"presentedFrames"] ?: @0, @"fps":status[@"measuredFPS"] ?: @0}];
        lastSample = sinceStart;
      }
      if (ready && -ready.timeIntervalSinceNow >= hold) break;
      // Exercise the same pause/resume command path used by sleep/focus policy.
      if (ready && !pauseSent && -ready.timeIntervalSinceNow >= hold * .35) {
        player.sleeping = YES; [player tick]; pauseSent = YES;
      }
      if (ready && pauseSent && !resumeSent && -ready.timeIntervalSinceNow >= hold * .6) {
        player.sleeping = NO; [player tick]; resumeSent = YES;
      }
    }
  }
  NSDate *lastHeartbeat = statusPath ? [fm attributesOfItemAtPath:statusPath error:nil][NSFileModificationDate] : nil;
  BOOL sustained = ready && -ready.timeIntervalSinceNow >= hold && player.sessions.count && !reportedError && !status[@"error"] &&
      lastHeartbeat && -lastHeartbeat.timeIntervalSinceNow < 4 && [status[@"mouseIgnored"] boolValue] &&
      [status[@"level"] integerValue] == CGWindowLevelForKey(kCGDesktopWindowLevelKey);
  NSMutableDictionary *record = [@{@"project":project, @"launched":@(launched), @"sustained_window":@(sustained),
    @"seconds":@(-started.timeIntervalSinceNow), @"pause_requested":@(pauseSent), @"resume_requested":@(resumeSent),
    @"session_locked_at_start":@(initiallyLocked), @"phase_samples":samples,
    @"error":reportedError ?: error.localizedDescription ?: @"", @"window":status ?: @{},
    @"visual_verification":@"pending", @"windows_parity":@"not established"} mutableCopy];
  for (NSString *name in @[@"playback.log", @"control.log", @"window.json"]) {
    NSString *source = [session[@"directory"] stringByAppendingPathComponent:name];
    if (source && [fm fileExistsAtPath:source]) {
      NSString *destination = [output stringByAppendingPathComponent:name];
      if (![fm fileExistsAtPath:destination]) [fm copyItemAtPath:source toPath:destination error:nil];
    }
  }
  [player stopAll]; Pump(.5);
  record[@"sessions_after_stop"] = @(player.sessions.count);
  BOOL windowRemains = NO;
  NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));
  for (NSDictionary *window in windows) {
    if ([window[(id)kCGWindowOwnerPID] isEqual:status[@"pid"]] &&
        [window[(id)kCGWindowNumber] isEqual:status[@"window"]]) windowRemains = YES;
  }
  record[@"window_after_stop"] = @(windowRemains);
  sustained = sustained && !windowRemains;
  [[NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingPrettyPrinted error:nil]
      writeToFile:[output stringByAppendingPathComponent:@"result.json"] atomically:YES];
  [NSNotificationCenter.defaultCenter removeObserver:observer];
  puts(sustained ? "sustained_window; visual verification pending" : "launch_or_stability_failure");
  return sustained ? 0 : 1;
} }
