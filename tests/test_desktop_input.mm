#import "../playback/DesktopInputPolicy.h"
static NSDictionary *Window(NSInteger level, CGRect bounds, double alpha) {
  return @{(id)kCGWindowLayer:@(level), (id)kCGWindowAlpha:@(alpha),
           (id)kCGWindowBounds:CFBridgingRelease(CGRectCreateDictionaryRepresentation(bounds))};
}
int main() { @autoreleasepool {
  CGPoint pointer = CGPointMake(500, 400);
  NSDictionary *desktop = Window(-2147483603, CGRectMake(0, 0, 1470, 956), 1);
  NSCAssert(LWDesktopPointIsExposed(@[desktop], pointer), @"Desktop icons must remain usable");
  NSDictionary *app = Window(0, CGRectMake(100, 100, 900, 600), 1);
  NSCAssert(!LWDesktopPointIsExposed(@[desktop,app], pointer), @"Never replay foreground app clicks");
  NSCAssert(!LWDesktopPointIsExposed(@[Window(-1,CGRectMake(0,0,1470,956),1)],pointer), @"Negative app overlays are not desktop windows");
  NSCAssert(LWDesktopPointIsExposed(@[app], CGPointMake(1400, 900)), @"Uncovered desktop exposed");
  NSCAssert(!LWDesktopPointIsExposed(@[Window(24, CGRectMake(0, 0, 1470, 24),1)], CGPointMake(500, 10)), @"Menu bar blocked");
  NSCAssert(LWDesktopPointIsExposed(@[Window(0,CGRectMake(0,0,1470,956),0)],pointer), @"Invisible overlay ignored");
  NSCAssert(!LWDesktopPointIsExposed(nil,pointer), @"Unknown window inventory fails closed");
  NSMutableDictionary *receiver = [app mutableCopy]; receiver[(id)kCGWindowNumber] = @42;
  NSCAssert(!LWDesktopEventTargetIsDesktop(@[receiver],42), @"Original foreground receiver remains blocked after pointer motion");
  NSCAssert(!LWDesktopEventTargetIsDesktop(@[],42), @"Closed original receiver is not a desktop click");
  receiver = [desktop mutableCopy]; receiver[(id)kCGWindowNumber] = @1;
  NSCAssert(LWDesktopEventTargetIsDesktop(@[receiver],1), @"Desktop receiver accepted");
  NSLog(@"Desktop input occlusion policy passed");
} return 0; }
