#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Window metadata only. Never capture another application's image or forward
// its mouse input to the wallpaper. Finder's desktop/icon layers are negative.
static BOOL LWDesktopPointIsExposed(NSArray<NSDictionary *> *windows, CGPoint point) {
  if (!windows) return NO;
  for (NSDictionary *window in windows) {
    if ([window[(id)kCGWindowLayer] integerValue] <= CGWindowLevelForKey(kCGDesktopIconWindowLevelKey)) continue;
    NSNumber *alpha = window[(id)kCGWindowAlpha];
    if (alpha && alpha.doubleValue <= .01) continue;
    NSDictionary *description = window[(id)kCGWindowBounds];
    if (![description isKindOfClass:NSDictionary.class]) return NO;
    CGRect bounds;
    if (CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)description, &bounds) &&
        CGRectContainsPoint(bounds, point)) return NO;
  }
  return YES;
}

static BOOL LWDesktopEventTargetIsDesktop(NSArray<NSDictionary *> *windows, CGWindowID target) {
  if (!target) return YES; // Some mouse sources omit the window field; still apply point occlusion.
  for (NSDictionary *window in windows)
    if ([window[(id)kCGWindowNumber] unsignedIntValue] == target)
      return [window[(id)kCGWindowLayer] integerValue] <= CGWindowLevelForKey(kCGDesktopIconWindowLevelKey);
  return NO; // A closed/unknown original receiver is not a desktop click.
}
