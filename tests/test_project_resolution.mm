#import <Foundation/Foundation.h>
#import "../playback/WallpaperProject.h"
int main(int argc, const char **argv) { @autoreleasepool {
  NSString *root = [NSString stringWithUTF8String:argv[1]];
  NSCAssert(LWProjectJSON([root stringByAppendingPathComponent:@"1000000001.weproject"]), @"Scene library entry must resolve");
  NSCAssert(LWPlayablePath([root stringByAppendingPathComponent:@"1000000002.weproject"]), @"Second original Scene must resolve");
  NSCAssert(!LWPlayablePath([root stringByAppendingPathComponent:@"missing.weproject"]), @"Missing project must fail");
  NSLog(@"Project resolver passed");
} return 0; }
