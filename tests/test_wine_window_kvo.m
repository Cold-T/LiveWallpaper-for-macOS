#import <AppKit/AppKit.h>
#import "../playback/desktop_window_bridge.m"
@interface WineWindow : NSWindow
@property NSInteger watchedValue;
@end
@implementation WineWindow
- (void)orderFront:(id)sender {}
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end
@interface WindowObserver : NSObject
@property NSUInteger changes;
@end
@implementation WindowObserver
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context { self.changes++; }
@end
static void Check(BOOL value, const char *message) {
  if (!value) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static WineWindow *NewWindow(void) {
  return [[WineWindow alloc] initWithContentRect:NSMakeRect(0, 0, 10, 10)
      styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:YES];
}
static void CheckSetters(WineWindow *window) {
  window.level = NSNormalWindowLevel;
  window.styleMask = NSWindowStyleMaskTitled;
  window.collectionBehavior = NSWindowCollectionBehaviorDefault;
  Check(window.level == DesktopLevel(), "level forwarded through original IMP");
  Check(window.styleMask == NSWindowStyleMaskBorderless, "style forwarded through original IMP");
  Check(window.collectionBehavior == DesktopBehavior(), "behavior forwarded through original IMP");
  Check(!window.canBecomeKeyWindow && !window.canBecomeMainWindow, "selected window stays nonactivatable");
}
int main(void) {
 @autoreleasepool {
  [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
  WindowObserver *observer = [WindowObserver new];
  // Create an observation before any policy IMP is installed, including a
  // setter that KVO may cache. Its object identity and callbacks must survive.
  WineWindow *before = NewWindow();
  [before addObserver:observer forKeyPath:@"level" options:0 context:NULL];
  Class beforeClass = object_getClass(before);
  WineWindow *window = NewWindow(); Class originalClass = object_getClass(window);
  Check(AdaptWindow(window), "initial adaptation");
  Check(object_getClass(window) == originalClass, "do not change object isa");
  [window addObserver:observer forKeyPath:@"watchedValue" options:0 context:NULL];
  Class observed = object_getClass(window);
  Check(observed != originalClass && IsWineWindow(window), "real KVO installed");
  Check(AdaptWindow(window), "recognize Wine window beneath KVO");
  Check(object_getClass(window) == observed, "retain observer class");
  CheckSetters(window); NSUInteger count = observer.changes; window.watchedValue = 1;
  Check(observer.changes == count + 1, "observer receives actual changes");
  [window removeObserver:observer forKeyPath:@"watchedValue"];
  Check(AdaptWindow(window), "adapt after observer removal"); CheckSetters(window);
  Check(AdaptWindow(before), "support preexisting observation");
  Check(object_getClass(before) == beforeClass, "preexisting KVO isa retained");
  count = observer.changes; CheckSetters(before);
  Check(observer.changes > count, "cached KVO setter still notifies");
  [before removeObserver:observer forKeyPath:@"level"];
  Check(AdaptWindow(before), "adapt after preexisting observer removal"); CheckSetters(before);
  WineWindow *other = NewWindow();
  other.level = NSNormalWindowLevel; other.styleMask = NSWindowStyleMaskTitled;
  other.collectionBehavior = NSWindowCollectionBehaviorDefault;
  Check(other.level == NSNormalWindowLevel && other.styleMask == NSWindowStyleMaskTitled &&
        other.collectionBehavior == NSWindowCollectionBehaviorDefault && other.canBecomeKeyWindow,
        "unselected Wine windows retain their exact original behavior");
  NSWindow *unrelated = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,10,10) styleMask:0 backing:NSBackingStoreBuffered defer:YES];
  Check(!AdaptWindow(unrelated), "reject unrelated native windows");
 }
 puts("PASS: KVO before/after adaptation; original setter dispatch and notifications; scope; window deallocation");
}
