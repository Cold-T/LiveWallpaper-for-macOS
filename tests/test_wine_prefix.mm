#import "../playback/WinePrefix.h"
int main() { @autoreleasepool {
  NSFileManager *fm = NSFileManager.defaultManager;
  NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
  NSError *error = nil;
  NSCAssert(LWSetWineRetina(root, YES, &error), @"Fresh registry: %@", error);
  NSString *path = [root stringByAppendingPathComponent:@"user.reg"];
  NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
  NSCAssert([text containsString:@"[Software\\\\Wine\\\\Mac Driver]\n\"RetinaMode\"=\"Y\""], @"Correct Wine-escaped section");
  NSCAssert(LWSetWineRetina(root, YES, &error), @"Idempotent setup");
  NSCAssert([[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] isEqual:text], @"Unchanged registry remains byte-identical");
  NSString *fixture = @"WINE REGISTRY Version 2\n#arch=win64\n[Software\\\\Wine\\\\Mac Driver] 123\n\"Keep\"=\"value\"\n\"RetinaMode\"=hex:01,\\\n  00\n[Other] 456\n\"Key\"=dword:0000002a\n";
  [fixture writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
  NSCAssert(LWSetWineRetina(root, NO, &error), @"Existing registry");
  text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
  NSCAssert([text containsString:@"\"RetinaMode\"=\"N\""] && ![text containsString:@"  00"], @"Existing multiline value replaced");
  NSCAssert([text containsString:@"\"Keep\"=\"value\""] && [text containsString:@"[Other] 456\n\"Key\"=dword:0000002a"], @"Other settings preserved");
  [@"invalid data" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
  NSCAssert(!LWSetWineRetina(root, YES, &error), @"Malformed file refused");
  NSCAssert([[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] isEqual:@"invalid data"], @"Malformed file preserved");
  [fm removeItemAtPath:path error:nil];
  [fm createSymbolicLinkAtPath:path withDestinationPath:@"/missing/external-registry" error:nil];
  NSCAssert(!LWSetWineRetina(root, YES, &error), @"External/dangling registry symlink refused");
  [fm removeItemAtPath:root error:nil];
  NSLog(@"Wine prefix Retina preparation passed");
} return 0; }
