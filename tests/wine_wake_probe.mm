#import "../playback/WinePlayback.h"
static void Pump(double seconds) { NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds]; while(end.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]]; }
static BOOL Ready(LWWinePlayback *player, double timeout) {
  NSDate *end=[NSDate dateWithTimeIntervalSinceNow:timeout];
  while(end.timeIntervalSinceNow>0) {
    Pump(.2); NSDictionary *s=player.sessions.allValues.firstObject;
    if([s[@"playbackStarted"] boolValue] && [s[@"controlApplied"] boolValue]) return YES;
  } return NO;
}
int main(int argc,const char **argv) { @autoreleasepool {
  [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
  // Process-local test override. Never change the user's saved audio setting.
  [NSUserDefaults.standardUserDefaults setVolatileDomain:@{@"wallpapervolume":@0,@"pauseOnAppFocus":@NO} forName:NSArgumentDomain];
  LWWinePlayback *player=[LWWinePlayback new]; __block NSUInteger errors=0;
  id observer=[NSNotificationCenter.defaultCenter addObserverForName:@"LWWinePlaybackError" object:nil queue:nil usingBlock:^(NSNotification *note){errors++;NSLog(@"PROBE ERROR %@",note.object);}];
  NSString *project=[NSString stringWithUTF8String:argv[1]]; NSError *error=nil;
  BOOL start=[player start:project screen:NSScreen.mainScreen error:&error];
  BOOL initial=start && Ready(player,60); NSLog(@"PROBE initial=%d error=%@",initial,error);
  BOOL resumed=NO,restarted=NO;
  if(initial) {
    NSString *uuid=player.sessions.allKeys.firstObject; NSTask *old=player.sessions[uuid][@"task"];
    [player sleep:nil]; Pump(2); [player wake:nil]; Pump(17);
    resumed=player.sessions[uuid][@"task"]==old && [player.sessions[uuid][@"controlApplied"] boolValue] && ![player.sessions[uuid][@"paused"] boolValue];
    NSLog(@"PROBE healthy_resume=%d",resumed);
    [player sleep:nil];
    NSDictionary *s=player.sessions[uuid];
    // Simulate a renderer lost during sleep, without sleeping the user's Mac.
    BOOL stopped=[player stopPrefix:s[@"prefix"] runtime:s[@"runtime"] directory:s[@"directory"] error:&error];
    NSLog(@"PROBE simulated_renderer_loss=%d",stopped);
    [player wake:nil]; Pump(17);
    restarted=Ready(player,60) && player.sessions[uuid][@"task"]!=old;
    NSLog(@"PROBE automatic_restart=%d errors=%lu",restarted,(unsigned long)errors);
  }
  [player stopAll]; Pump(.5); [NSNotificationCenter.defaultCenter removeObserver:observer];
  BOOL ok=initial && resumed && restarted && !errors && !player.sessions.count;
  printf("%s live Wine wake recovery (muted)\n",ok?"PASS":"FAIL"); return ok?0:1;
} }
