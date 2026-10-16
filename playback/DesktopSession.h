#pragma once
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

static BOOL LWDesktopSessionIsLocked(void) {
  NSDictionary *session = CFBridgingRelease(CGSessionCopyCurrentDictionary());
  if (!session) return YES;
  NSNumber *onConsole = session[(__bridge NSString *)kCGSessionOnConsoleKey];
  NSNumber *loggedIn = session[(__bridge NSString *)kCGSessionLoginDoneKey];
  return [session[@"CGSSessionScreenIsLocked"] boolValue] ||
      (onConsole && !onConsole.boolValue) || (loggedIn && !loggedIn.boolValue) ||
      [NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier isEqualToString:@"com.apple.loginwindow"];
}
