#import <Foundation/Foundation.h>
#import "../playback/WineCompatibility.h"
int main() { @autoreleasepool {
  unsetenv("LIVEWALLPAPER_WINE_QUALITY");
  NSFileManager *fm = NSFileManager.defaultManager;
  NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  NSString *runtime = [root stringByAppendingPathComponent:@"runtime"];
  NSString *engine = [runtime stringByAppendingPathComponent:@"engine"];
  NSString *source = [engine stringByAppendingPathComponent:@"assets/fonts"];
  NSString *prefix = [root stringByAppendingPathComponent:@"prefix"];
  NSString *target = [prefix stringByAppendingPathComponent:@"drive_c/windows/Fonts/consola.ttf"];
  [fm createDirectoryAtPath:[target stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
  [@"font bytes" writeToFile:target atomically:YES encoding:NSUTF8StringEncoding error:nil];
  [fm createDirectoryAtPath:source withIntermediateDirectories:YES attributes:nil error:nil];
  [@"font bytes" writeToFile:[source stringByAppendingPathComponent:@"RobotoMono-Regular.ttf"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
  NSString *config = [engine stringByAppendingPathComponent:@"config.json"];
  [@"{\"account\":{\"general\":{\"user\":{\"mediaintegration\":true,\"keep\":42}}}}" writeToFile:config atomically:YES encoding:NSUTF8StringEncoding error:nil];
  NSError *error = nil;
  NSCAssert(LWPrepareWineCompatibility(runtime, prefix, &error), @"Initial preparation: %@", error);
  NSCAssert([[NSString stringWithContentsOfFile:target encoding:NSUTF8StringEncoding error:nil] isEqualToString:@"font bytes"], @"Existing exact font filename was preserved");
  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:config] options:0 error:nil];
  NSCAssert([json[@"account"][@"general"][@"user"][@"mediaintegration"] isEqual:@NO], @"Unsupported Windows media integration disabled");
  NSCAssert([json[@"account"][@"general"][@"user"][@"keep"] isEqual:@42], @"Unrelated config preserved");
  NSCAssert([json[@"account"][@"general"][@"user"][@"fps"] isEqual:@15] &&
      [json[@"account"][@"general"][@"user"][@"postprocessing"] isEqual:@"enabled"], @"Silent first launch matches shipped medium default");
  setenv("LIVEWALLPAPER_WINE_QUALITY", "ultra", 1);
  NSCAssert(LWPrepareWineCompatibility(runtime, prefix, &error), @"Explicit comparison preset");
  json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:config] options:0 error:nil];
  NSCAssert([json[@"account"][@"general"][@"user"][@"fps"] isEqual:@30] &&
      [json[@"account"][@"general"][@"user"][@"postprocessing"] isEqual:@"ultra"], @"Full shipped ultra preset applied");
  unsetenv("LIVEWALLPAPER_WINE_QUALITY");
  NSCAssert(LWPrepareWineCompatibility(runtime, prefix, &error), @"Existing quality preserved");
  json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:config] options:0 error:nil];
  NSCAssert([json[@"account"][@"general"][@"user"][@"fps"] isEqual:@30], @"No silent reset to medium");
  NSData *beforeInvalid = [NSData dataWithContentsOfFile:config];
  setenv("LIVEWALLPAPER_WINE_QUALITY", "unknown", 1);
  NSCAssert(!LWPrepareWineCompatibility(runtime, prefix, &error), @"Unknown preset rejected");
  NSCAssert([[NSData dataWithContentsOfFile:config] isEqual:beforeInvalid], @"Unknown preset does not mutate config");
  unsetenv("LIVEWALLPAPER_WINE_QUALITY");
  [@"existing font" writeToFile:target atomically:YES encoding:NSUTF8StringEncoding error:nil];
  NSCAssert(LWPrepareWineCompatibility(runtime, prefix, &error), @"Idempotent");
  NSCAssert([[NSString stringWithContentsOfFile:target encoding:NSUTF8StringEncoding error:nil] isEqualToString:@"existing font"], @"Existing font preserved");
  [fm removeItemAtPath:[target stringByDeletingLastPathComponent] error:nil];
  NSString *outside = [root stringByAppendingPathComponent:@"outside"];
  [fm createDirectoryAtPath:outside withIntermediateDirectories:YES attributes:nil error:nil];
  [fm createSymbolicLinkAtPath:[target stringByDeletingLastPathComponent] withDestinationPath:outside error:nil];
  NSCAssert(!LWPrepareWineCompatibility(runtime, prefix, &error), @"Escaping font symlink rejected");
  NSCAssert(![fm fileExistsAtPath:[outside stringByAppendingPathComponent:@"consola.ttf"]], @"No write outside prefix");
  [fm removeItemAtPath:root error:nil];
  NSLog(@"Wine compatibility preparation passed");
} return 0; }
