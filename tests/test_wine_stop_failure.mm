#import "../playback/WinePlayback.h"

@interface StopFailurePlayer : LWWinePlayback
@property BOOL allowStop;
@end
@implementation StopFailurePlayer
- (BOOL)stopPrefix:(NSString *)prefix runtime:(NSString *)runtime directory:(NSString *)directory error:(NSError **)error {
  if (!self.allowStop && error) *error = [NSError errorWithDomain:@"fixture" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Simulated registry flush failure"}];
  return self.allowStop;
}
@end

int main() { @autoreleasepool {
  StopFailurePlayer *player = [StopFailurePlayer new];
  player.sessions[@"test-display"] = @{@"runtime":@"/unused", @"prefix":@"/unused/prefix", @"directory":@"/unused"};
  __block NSUInteger errors = 0;
  id observer = [NSNotificationCenter.defaultCenter addObserverForName:@"LWWinePlaybackError" object:nil queue:nil usingBlock:^(NSNotification *note) { errors++; }];
  NSCAssert(![player stopDisplay:@"test-display"], @"Failed stop must be reported");
  NSCAssert(player.sessions.count == 1 && errors == 1, @"Failed cleanup must retain ownership for retry");
  player.allowStop = YES;
  NSCAssert([player stopDisplay:@"test-display"] && !player.sessions.count, @"Successful retry must release ownership");
  NSCAssert([player stopDisplay:@"test-display"], @"Already stopped is successful");
  [NSNotificationCenter.defaultCenter removeObserver:observer];
  NSLog(@"Wine failed-stop ownership and retry passed");
} return 0; }
