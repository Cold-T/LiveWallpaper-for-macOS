// Opt-in experiment for a user-owned Wine process. Does not change PE code,
// Steam integration, authentication, or licensing. Remove the launch environment
// variables to disable it. Only the exact requested window title is adapted.
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "DesktopInputPolicy.h"
#import "DesktopSession.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdatomic.h>

static dispatch_source_t probeTimer;
static NSMapTable<NSWindow *, NSString *> *lastStates;
static NSString *targetTitle;
static BOOL desktopEnabled;
static id desktopMouseMonitor;
static __weak NSWindow *desktopInputWindow;
static NSUInteger desktopMouseEvents;
static NSUInteger forwardedButtons;
static BOOL inputLocked;
static CGEventRef lastDesktopButtonEvent;
static atomic_uint_fast64_t presentedFrameCount;
static __weak CAMetalLayer *measuredLayer;
static _Atomic(IMP) originalNextDrawableMethod;
static BOOL continuousRenderStats;

// Observe one real presentation for startup readiness; continuous counting
// remains opt-in. No texture readback or image capture.
static id<CAMetalDrawable> NextDrawableWithTiming(id layer, SEL selector) {
  IMP original = atomic_load_explicit(&originalNextDrawableMethod, memory_order_acquire);
  id<CAMetalDrawable> drawable = ((id<CAMetalDrawable> (*)(id, SEL))original)(layer, selector);
  if (drawable && objc_getAssociatedObject(layer, &presentedFrameCount) &&
      (continuousRenderStats || !atomic_load_explicit(&presentedFrameCount, memory_order_relaxed))) {
    [drawable addPresentedHandler:^(id<MTLDrawable> presented) {
      atomic_fetch_add_explicit(&presentedFrameCount, 1, memory_order_relaxed);
    }];
  }
  return drawable;
}

static void FindMetalLayer(CALayer *layer, CAMetalLayer **largest) {
  if (!layer) return;
  if ([layer isKindOfClass:CAMetalLayer.class]) {
    CAMetalLayer *candidate = (CAMetalLayer *)layer;
    if (!*largest || candidate.drawableSize.width * candidate.drawableSize.height >
        (*largest).drawableSize.width * (*largest).drawableSize.height) *largest = candidate;
  }
  for (CALayer *child in layer.sublayers) FindMetalLayer(child, largest);
}

static void FindViewMetalLayer(NSView *view, CAMetalLayer **largest) {
  FindMetalLayer(view.layer, largest);
  for (NSView *child in view.subviews) FindViewMetalLayer(child, largest);
}

static void ObserveRenderTiming(NSWindow *window) {
  continuousRenderStats = getenv("LW_WINE_RENDER_STATS") && !strcmp(getenv("LW_WINE_RENDER_STATS"), "1");
  CAMetalLayer *largest = nil;
  FindViewMetalLayer(window.contentView, &largest);
  if (!largest) return;
  if (!atomic_load_explicit(&originalNextDrawableMethod, memory_order_acquire)) {
    Method method = class_getInstanceMethod(CAMetalLayer.class, @selector(nextDrawable));
    if (!method) return;
    atomic_store_explicit(&originalNextDrawableMethod, method_getImplementation(method), memory_order_release);
    method_setImplementation(method, (IMP)NextDrawableWithTiming);
  }
  if (measuredLayer != largest) {
    if (measuredLayer) objc_setAssociatedObject(measuredLayer, &presentedFrameCount, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    measuredLayer = largest;
    objc_setAssociatedObject(largest, &presentedFrameCount, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }
}

static BOOL DeliverDesktopMouse(NSWindow *target, NSEvent *event, SEL handler) {
  id owner = NSApp.delegate;
  SEL getCapture = NSSelectorFromString(@"mouseCaptureWindow"), setCapture = NSSelectorFromString(@"setMouseCaptureWindow:");
  if (![owner respondsToSelector:getCapture] || ![owner respondsToSelector:setCapture] || ![owner respondsToSelector:handler]) return NO;
  id previous = ((id (*)(id, SEL))objc_msgSend)(owner, getCapture);
  if (previous) return NO; // Respect real capture already owned by Wine.
  // This synthesized property changes only the callback's target pointer; it
  // does not call macdrv_set_mouse_capture or alter system mouse capture.
  ((void (*)(id, SEL, id))objc_msgSend)(owner, setCapture, target);
  @try { ((void (*)(id, SEL, id))objc_msgSend)(owner, handler, event); }
  @finally { ((void (*)(id, SEL, id))objc_msgSend)(owner, setCapture, previous); }
  desktopMouseEvents++;
  return YES;
}

static void ReleaseDesktopButtons(NSUInteger mask) {
  NSWindow *target = desktopInputWindow;
  if (!target || !lastDesktopButtonEvent) { forwardedButtons = 0; return; }
  for (NSUInteger button = 0; button < sizeof(NSUInteger) * 8; button++) {
    NSUInteger bit = 1UL << button;
    if (!(forwardedButtons & mask & bit)) continue;
    CGEventRef release = CGEventCreateCopy(lastDesktopButtonEvent);
    CGEventSetType(release, button == 0 ? kCGEventLeftMouseUp : button == 1 ? kCGEventRightMouseUp : kCGEventOtherMouseUp);
    CGEventSetIntegerValueField(release, kCGMouseEventButtonNumber, button);
    NSPoint pointer = NSEvent.mouseLocation;
    CGEventSetLocation(release, CGPointMake(pointer.x, NSMaxY(NSScreen.screens.firstObject.frame) - pointer.y));
    CGEventSetTimestamp(release, (CGEventTimestamp)(CACurrentMediaTime() * NSEC_PER_SEC));
    NSEvent *event = [NSEvent eventWithCGEvent:release];
    if (DeliverDesktopMouse(target, event, NSSelectorFromString(@"handleMouseButton:"))) forwardedButtons &= ~bit;
    CFRelease(release);
  }
}

// Wine's mouse controller normally receives events only for its Cocoa windows.
// Desktop windows stay click-through, so replay only mouse events over exposed
// desktop through that same controller. This never installs a keyboard monitor,
// suppresses an OS event, activates Wine, or sends a click to another Mac app.
static void StartDesktopInput(NSWindow *window) {
  if (!getenv("LW_WINE_DESKTOP_INPUT") || strcmp(getenv("LW_WINE_DESKTOP_INPUT"), "1")) return;
  if (desktopInputWindow != window) ReleaseDesktopButtons(forwardedButtons);
  desktopInputWindow = window;
  ReleaseDesktopButtons(forwardedButtons & ~NSEvent.pressedMouseButtons);
  if (desktopMouseMonitor) return;
  id controller = NSApp.delegate;
  for (NSString *name in @[@"mouseCaptureWindow", @"setMouseCaptureWindow:", @"handleMouseMove:", @"handleMouseButton:", @"handleScrollWheel:"])
    if (![controller respondsToSelector:NSSelectorFromString(name)]) {
      fprintf(stderr, "[LWBridge] Wine mouse controller does not expose %s; input forwarding unavailable\n", name.UTF8String);
      return;
    }
  NSDistributedNotificationCenter *notifications = NSDistributedNotificationCenter.defaultCenter;
  inputLocked = LWDesktopSessionIsLocked();
  [notifications addObserverForName:@"com.apple.screenIsLocked" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { ReleaseDesktopButtons(forwardedButtons); inputLocked = YES; }];
  [notifications addObserverForName:@"com.apple.screenIsUnlocked" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { inputLocked = NO; }];
  NSEventMask mask = NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged | NSEventMaskRightMouseDragged |
      NSEventMaskOtherMouseDragged | NSEventMaskLeftMouseDown | NSEventMaskLeftMouseUp |
      NSEventMaskRightMouseDown | NSEventMaskRightMouseUp | NSEventMaskOtherMouseDown |
      NSEventMaskOtherMouseUp | NSEventMaskScrollWheel;
  desktopMouseMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:mask handler:^(NSEvent *event) {
    NSWindow *target = desktopInputWindow;
    if (!target || !target.visible || inputLocked) return;
    NSEventType type = event.type;
    BOOL down = type == NSEventTypeLeftMouseDown || type == NSEventTypeRightMouseDown || type == NSEventTypeOtherMouseDown;
    BOOL up = type == NSEventTypeLeftMouseUp || type == NSEventTypeRightMouseUp || type == NSEventTypeOtherMouseUp;
    BOOL drag = type == NSEventTypeLeftMouseDragged || type == NSEventTypeRightMouseDragged || type == NSEventTypeOtherMouseDragged;
    NSUInteger bit = (down || up) && event.buttonNumber >= 0 && event.buttonNumber < sizeof(NSUInteger) * 8 ? (1UL << event.buttonNumber) : 0;
    BOOL ownedRelease = up && (forwardedButtons & bit);
    if (up && !ownedRelease) return;
    if (drag && !forwardedButtons) return;
    CGEventRef originalEvent = event.CGEvent;
    if (!originalEvent) return;
    CGPoint eventPoint = CGEventGetLocation(originalEvent);
    CGFloat top = NSMaxY(NSScreen.screens.firstObject.frame);
    NSPoint pointer = NSMakePoint(eventPoint.x, top - eventPoint.y);
    if (!ownedRelease) {
      if (!NSPointInRect(pointer, target.frame)) return;
      static NSArray *windowInventory;
      static NSTimeInterval inventoryTime;
      // Never reuse a motion cache for a button press or scroll event.
      if (down || up || type == NSEventTypeScrollWheel || event.timestamp - inventoryTime > .03) {
        windowInventory = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
        inventoryTime = event.timestamp;
      }
      if (!LWDesktopPointIsExposed(windowInventory, eventPoint)) return;
      CGWindowID originalTarget = (CGWindowID)CGEventGetIntegerValueField(originalEvent, kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent);
      if (!originalTarget) originalTarget = (CGWindowID)CGEventGetIntegerValueField(originalEvent, kCGMouseEventWindowUnderMousePointer);
      if (!LWDesktopEventTargetIsDesktop(windowInventory, originalTarget)) return;
    }
    SEL handler = NSSelectorFromString(down || up ? @"handleMouseButton:" : type == NSEventTypeScrollWheel ? @"handleScrollWheel:" : @"handleMouseMove:");
    if (DeliverDesktopMouse(target, event, handler)) {
      if (down) {
        forwardedButtons |= bit;
        if (lastDesktopButtonEvent) CFRelease(lastDesktopButtonEvent);
        lastDesktopButtonEvent = event.CGEvent ? CGEventCreateCopy(event.CGEvent) : NULL;
      }
      if (up) forwardedButtons &= ~bit;
    }
  }];
  fprintf(stderr, "[LWBridge] desktop mouse forwarding %s\n", desktopMouseMonitor ? "enabled" : "unavailable");
}
static NSInteger DesktopLevel(void) {
  // Measured on this host: system Wallpaper=desktop-2 and the existing native
  // player=desktop-1. Use desktop itself to avoid same-level ordering races;
  // Finder desktop icons remain twenty levels above this experimental window.
  return (NSInteger)CGWindowLevelForKey(kCGDesktopWindowLevelKey);
}

static NSWindowCollectionBehavior DesktopBehavior(void) {
  return NSWindowCollectionBehaviorCanJoinAllSpaces |
         NSWindowCollectionBehaviorStationary |
         NSWindowCollectionBehaviorIgnoresCycle |
         NSWindowCollectionBehaviorFullScreenAuxiliary;
}

// Keep Wine/AppKit's object and KVO class identities intact. Each policy
// captures the exact preceding IMP; observers may add another subclass later.
static char desktopWindowPolicyKey;
static NSMutableSet<NSValue *> *policyClasses;
static BOOL ClassHasAncestor(Class actual, Class expected) {
  if (!expected) return NO;
  for (Class candidate = actual; candidate; candidate = class_getSuperclass(candidate))
    if (candidate == expected) return YES;
  return NO;
}
static BOOL IsWineWindow(NSWindow *window) {
  return ClassHasAncestor(object_getClass(window), NSClassFromString(@"WineWindow"));
}
static BOOL HasDesktopPolicy(id window) {
  return [objc_getAssociatedObject(window, &desktopWindowPolicyKey) boolValue];
}
static BOOL DesktopCanBecomeKey(void) { return NO; }
static void ReplaceWineMethod(Class cls, SEL selector, IMP replacement, const char *types) {
  // class_getInstanceMethod may return a superclass's Method: never mutate
  // NSWindow's shared implementation when Wine inherits a setter.
  if (!class_addMethod(cls, selector, replacement, types))
    class_replaceMethod(cls, selector, replacement, types);
}
static BOOL InstallWindowPolicy(Class cls) {
  if (!policyClasses) policyClasses = [NSMutableSet set];
  NSValue *identity = [NSValue valueWithPointer:(__bridge const void *)cls];
  if ([policyClasses containsObject:identity]) return YES;
  SEL selectors[] = {@selector(setLevel:), @selector(setCollectionBehavior:),
      @selector(setStyleMask:), @selector(canBecomeKeyWindow), @selector(canBecomeMainWindow)};
  IMP previous[5]; const char *types[5];
  for (unsigned i = 0; i < 5; i++) {
    Method method = class_getInstanceMethod(cls, selectors[i]);
    if (!method) return NO;
    previous[i] = method_getImplementation(method); types[i] = method_getTypeEncoding(method);
  }
  IMP oldLevel = previous[0], oldBehavior = previous[1], oldStyle = previous[2];
  IMP level = imp_implementationWithBlock(^(id object, NSInteger requested) {
    ((void (*)(id, SEL, NSInteger))oldLevel)(object, @selector(setLevel:),
        HasDesktopPolicy(object) ? DesktopLevel() : requested);
  });
  IMP behavior = imp_implementationWithBlock(^(id object, NSWindowCollectionBehavior requested) {
    ((void (*)(id, SEL, NSWindowCollectionBehavior))oldBehavior)(object, @selector(setCollectionBehavior:),
        HasDesktopPolicy(object) ? DesktopBehavior() : requested);
  });
  IMP style = imp_implementationWithBlock(^(id object, NSWindowStyleMask requested) {
    ((void (*)(id, SEL, NSWindowStyleMask))oldStyle)(object, @selector(setStyleMask:),
        HasDesktopPolicy(object) ? NSWindowStyleMaskBorderless : requested);
  });
  IMP replacements[5] = {level, behavior, style, NULL, NULL};
  for (unsigned i = 3; i < 5; i++) {
    IMP original = previous[i]; SEL selector = selectors[i];
    replacements[i] = imp_implementationWithBlock(^BOOL(id object) {
      return HasDesktopPolicy(object) ? DesktopCanBecomeKey() : ((BOOL (*)(id, SEL))original)(object, selector);
    });
  }
  for (unsigned i = 0; i < 5; i++) {
    if (!replacements[i]) {
      for (unsigned j = 0; j < 5; j++) if (replacements[j]) imp_removeBlock(replacements[j]);
      return NO;
    }
  }
  // Window adaptation and observer discovery both run on the main queue.
  for (unsigned i = 0; i < 5; i++) ReplaceWineMethod(cls, selectors[i], replacements[i], types[i]);
  [policyClasses addObject:identity];
  return YES;
}
static BOOL AdaptWindow(NSWindow *window) {
  if (!IsWineWindow(window)) {
    fprintf(stderr, "[LWBridge] refusing unexpected window class %s\n", class_getName(object_getClass(window)));
    return NO;
  }
  BOOL alreadyAdapted = HasDesktopPolicy(window);
  if (!InstallWindowPolicy(object_getClass(window))) return NO;
  objc_setAssociatedObject(window, &desktopWindowPolicyKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  if (window.styleMask != NSWindowStyleMaskBorderless) window.styleMask = NSWindowStyleMaskBorderless;
  if (window.level != DesktopLevel()) window.level = DesktopLevel();
  if (window.collectionBehavior != DesktopBehavior()) window.collectionBehavior = DesktopBehavior();
  window.ignoresMouseEvents = YES;
  window.hasShadow = NO;
  window.hidesOnDeactivate = NO;
  BOOL syncWineFrame = NO;
  if (getenv("LW_WINE_DESKTOP_FILL")) {
    NSScreen *screen = nil;
    const char *requested = getenv("LW_WINE_DISPLAY_UUID");
    for (NSScreen *candidate in NSScreen.screens) {
      CGDirectDisplayID display = [candidate.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
      CFUUIDRef identifier = CGDisplayCreateUUIDFromDisplayID(display);
      if (!identifier) continue;
      NSString *uuid = CFBridgingRelease(CFUUIDCreateString(NULL, identifier)); CFRelease(identifier);
      if (requested && [uuid isEqualToString:[NSString stringWithUTF8String:requested]]) { screen = candidate; break; }
    }
    if (!requested) screen = window.screen ?: NSScreen.mainScreen;
    if (!screen) { [window orderOut:nil]; return YES; }
    if (screen && (!alreadyAdapted || !NSEqualRects(window.frame, screen.frame))) {
      syncWineFrame = YES;
      SEL updateWineFrame = NSSelectorFromString(@"setFrameAndWineFrame:");
      if ([window respondsToSelector:updateWineFrame]) {
        ((void (*)(id, SEL, NSRect))objc_msgSend)(window, updateWineFrame, screen.frame);
      } else {
        [window setFrame:screen.frame display:YES];
      }
    }
  }
  if (!alreadyAdapted || !window.visible) [window orderFront:nil];
  // Wine reports the final visible frame after updating its cached wineFrame
  // in setFrameFromWine/order paths. Keep its Windows backend in sync after our
  // own first adaptation or display-size change, even if Cocoa was already fit.
  SEL frameChanged = NSSelectorFromString(@"windowDidResize:skipSizeMove:");
  if (syncWineFrame && window.visible && [window respondsToSelector:frameChanged])
    ((void (*)(id, SEL, id, BOOL))objc_msgSend)(window, frameChanged, nil, YES);
  StartDesktopInput(window);
  ObserveRenderTiming(window);
  const char *statusFile = getenv("LW_WINE_STATUS_FILE");
  if (statusFile) {
    NSMutableDictionary *state = [@{@"pid":@(getpid()), @"window":@(window.windowNumber),
      @"level":@(window.level), @"frame":NSStringFromRect(window.frame), @"mouseIgnored":@(window.ignoresMouseEvents),
      @"inputEnabled":@(desktopMouseMonitor != nil), @"forwardedMouseEvents":@(desktopMouseEvents)} mutableCopy];
    // Observe the real render view in points; correcting its validated Win32
    // child is the supervisor's job. Never force a Metal drawable/backbuffer.
    CAMetalLayer *renderLayer = nil;
    FindViewMetalLayer(window.contentView, &renderLayer);
    state[@"rendererReady"] = @(renderLayer != nil);
    state[@"firstFramePresented"] = @(atomic_load_explicit(&presentedFrameCount, memory_order_relaxed) > 0);
    if (renderLayer) {
      NSSize targetSize = window.contentView.bounds.size;
      NSSize renderSize = renderLayer.bounds.size;
      state[@"rendererSizeMismatch"] = @(fabs(renderSize.width - targetSize.width) > .5 ||
                                            fabs(renderSize.height - targetSize.height) > .5);
    }
    if (getenv("LW_WINE_RENDER_STATS")) {
      static uint64_t previousFrames;
      static NSTimeInterval previousTime;
      uint64_t frames = atomic_load_explicit(&presentedFrameCount, memory_order_relaxed);
      NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
      state[@"presentedFrames"] = @(frames);
      state[@"measuredFPS"] = previousTime && now > previousTime ? @((frames - previousFrames) / (now - previousTime)) : @0;
      state[@"drawablePixels"] = measuredLayer ? NSStringFromSize(measuredLayer.drawableSize) : @"unavailable";
      state[@"backingScale"] = @(window.backingScaleFactor);
      previousFrames = frames; previousTime = now;
    }
    [[NSJSONSerialization dataWithJSONObject:state options:0 error:nil]
      writeToFile:[NSString stringWithUTF8String:statusFile] atomically:YES];
  }
  if (alreadyAdapted) return YES;
  fprintf(stderr, "[LWBridge] adapted pid=%d number=%ld title=%s level=%ld\n",
          getpid(), (long)window.windowNumber, window.title.UTF8String,
          (long)window.level);
  return YES;
}

static void ObserveWindows(void) {
  @autoreleasepool {
    if (!NSApp) return;
    if (!lastStates) lastStates = [NSMapTable weakToStrongObjectsMapTable];
    for (NSWindow *window in NSApp.windows) {
      if (window.visible && [window.title isEqualToString:@"Error"] &&
          IsWineWindow(window)) {
        const char *statusFile = getenv("LW_WINE_STATUS_FILE");
        if (statusFile) {
          NSDictionary *error = @{@"error":@"Original engine displayed an Error dialog.", @"pid":@(getpid()), @"window":@(window.windowNumber)};
          [[NSJSONSerialization dataWithJSONObject:error options:0 error:nil]
            writeToFile:[NSString stringWithUTF8String:statusFile] atomically:YES];
        }
        return;
      }
    }
    for (NSWindow *window in NSApp.windows) {
      BOOL target = [window.title isEqualToString:targetTitle];
      if (target && desktopEnabled) AdaptWindow(window);
      NSString *state = [NSString stringWithFormat:@"%@|%ld|%d|%@|%@|mouseIgnored=%d",
          window.title, (long)window.level, window.visible,
          NSStringFromRect(window.frame), NSStringFromClass(window.class), window.ignoresMouseEvents];
      if (![[lastStates objectForKey:window] isEqualToString:state]) {
        [lastStates setObject:state forKey:window];
        fprintf(stderr, "[LWBridge] pid=%d number=%ld target=%d %s\n",
                getpid(), (long)window.windowNumber, target, state.UTF8String);
      }
    }
  }
}

__attribute__((constructor)) static void StartBridge(void) {
  const char *title = getenv("LW_WINE_TARGET_TITLE");
  if (!title || !*title) return;
  @autoreleasepool {
    targetTitle = [[NSString alloc] initWithUTF8String:title];
    desktopEnabled = getenv("LW_WINE_DESKTOP_ENABLE") &&
        strcmp(getenv("LW_WINE_DESKTOP_ENABLE"), "1") == 0;
    fprintf(stderr, "[LWBridge] loaded pid=%d desktop=%d title=%s\n",
            getpid(), desktopEnabled, title);
    dispatch_async(dispatch_get_main_queue(), ^{
      probeTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                          dispatch_get_main_queue());
      dispatch_source_set_timer(probeTimer, DISPATCH_TIME_NOW,
                                NSEC_PER_SEC / 2, NSEC_PER_SEC / 10);
      dispatch_source_set_event_handler(probeTimer, ^{ ObserveWindows(); });
      dispatch_resume(probeTimer);
    });
  }
}
