#import <Foundation/Foundation.h>
#import "../playback/WineFonts.h"

static void Put(NSString *path, NSString *text) {
  [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
      withIntermediateDirectories:YES attributes:nil error:nil];
  NSCAssert([text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil], @"fixture write");
}
int main() { @autoreleasepool {
  NSFileManager *fm = NSFileManager.defaultManager;
  NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  NSString *runtime = [root stringByAppendingPathComponent:@"runtime"];
  NSString *prefix = [root stringByAppendingPathComponent:@"prefix"];
  NSString *source = [root stringByAppendingPathComponent:@"installed-fonts"];
  NSString *fallback = [runtime stringByAppendingPathComponent:@"engine/assets/fonts/RobotoMono-Regular.ttf"];
  NSString *fonts = [prefix stringByAppendingPathComponent:@"drive_c/windows/Fonts"];
  Put(fallback, @"fallback");
  Put([source stringByAppendingPathComponent:@"Consola.ttf"], @"true-consolas");
  Put([source stringByAppendingPathComponent:@"Cambria.ttc"], @"true-cambria");
  Put([source stringByAppendingPathComponent:@"seguisym.ttf"], @"wrong-segoe-family");
  Put([source stringByAppendingPathComponent:@"ComicSansMSBold.ttf"], @"wrong-comic-style");
  NSError *error = nil;
  NSCAssert(!LWPrepareWineFontsWithRoots(runtime, prefix, @[@"relative-root"], &error), @"Relative roots rejected");
  NSCAssert(![fm fileExistsAtPath:fonts], @"Invalid roots do not mutate prefix");
  NSCAssert(LWPrepareWineFontsWithRoots(runtime, prefix, @[source], &error), @"prepare: %@", error);
  NSString *consolas = [fonts stringByAppendingPathComponent:@"consola.ttf"];
  NSCAssert([[fm destinationOfSymbolicLinkAtPath:consolas error:nil] isEqualToString:[source stringByAppendingPathComponent:@"Consola.ttf"]], @"Real font linked, not copied/fallback");
  NSCAssert([fm fileExistsAtPath:[fonts stringByAppendingPathComponent:@"cambria.ttc"]], @"Cambria exact target");
  NSCAssert(![fm fileExistsAtPath:[fonts stringByAppendingPathComponent:@"segoeui.ttf"]], @"Symbol font is not Segoe UI");
  NSCAssert(![fm fileExistsAtPath:[fonts stringByAppendingPathComponent:@"comic.ttf"]], @"Bold is not regular");
  NSCAssert(LWPrepareWineFontsWithRoots(runtime, prefix, @[], &error), @"Idempotent existing symlinks");
  [fm removeItemAtPath:consolas error:nil]; Put(consolas, @"user-font");
  NSCAssert(LWPrepareWineFontsWithRoots(runtime, prefix, @[source], &error), @"Preserve existing");
  NSCAssert([[NSString stringWithContentsOfFile:consolas encoding:NSUTF8StringEncoding error:nil] isEqual:@"user-font"], @"User font not replaced");
  [fm removeItemAtPath:consolas error:nil];
  [fm createSymbolicLinkAtPath:consolas withDestinationPath:@"/missing/user-font" error:nil];
  NSCAssert(LWPrepareWineFontsWithRoots(runtime, prefix, @[source], &error), @"Preserve dangling user link");
  NSCAssert([[fm destinationOfSymbolicLinkAtPath:consolas error:nil] isEqual:@"/missing/user-font"], @"Dangling user link not replaced");
  NSString *other = [root stringByAppendingPathComponent:@"outside"];
  Put([other stringByAppendingPathComponent:@"Consola.ttf"], @"outside-font");
  [fm removeItemAtPath:[source stringByAppendingPathComponent:@"Consola.ttf"] error:nil];
  [fm createSymbolicLinkAtPath:[source stringByAppendingPathComponent:@"Consola.ttf"] withDestinationPath:[other stringByAppendingPathComponent:@"Consola.ttf"] error:nil];
  [fm removeItemAtPath:consolas error:nil];
  NSCAssert(LWPrepareWineFontsWithRoots(runtime, prefix, @[source], &error), @"Source symlink outside root skipped");
  NSCAssert([[NSString stringWithContentsOfFile:consolas encoding:NSUTF8StringEncoding error:nil] isEqual:@"fallback"], @"Only fallback copied");
  [fm removeItemAtPath:fonts error:nil];
  [fm createSymbolicLinkAtPath:fonts withDestinationPath:other error:nil];
  NSCAssert(!LWPrepareWineFontsWithRoots(runtime, prefix, @[source], &error), @"Destination escape rejected");
  NSCAssert(![fm fileExistsAtPath:[other stringByAppendingPathComponent:@"cambria.ttc"]], @"No writes outside prefix");
  [fm removeItemAtPath:fonts error:nil];
  [fm removeItemAtPath:fallback error:nil];
  [fm createSymbolicLinkAtPath:fallback withDestinationPath:[other stringByAppendingPathComponent:@"Consola.ttf"] error:nil];
  NSCAssert(!LWPrepareWineFontsWithRoots(runtime, prefix, @[], &error), @"Fallback runtime escape rejected");
  NSCAssert(![fm fileExistsAtPath:[fonts stringByAppendingPathComponent:@"consola.ttf"]], @"Escaping fallback not copied");
  NSCAssert(LWWineFontFilenames().count == 8, @"Exact eight engine mappings");
  [fm removeItemAtPath:root error:nil];
  NSLog(@"Wine font preparation passed");
} return 0; }
