// Wine promotes itself when its first window is shown, overriding LSUIElement.
// Keep only LiveWallpaper-owned desktop processes out of Dock, Cmd-Tab and
// the menu bar. The native LiveWallpaper frontend is never injected.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

static BOOL (*originalPolicy)(id, SEL, NSApplicationActivationPolicy);
static BOOL DesktopPolicy(id app, SEL selector, NSApplicationActivationPolicy policy) {
    if (policy == NSApplicationActivationPolicyRegular)
        policy = NSApplicationActivationPolicyAccessory;
    return originalPolicy(app, selector, policy);
}
static void (*originalVisibility)(id, SEL, BOOL);
static NSStatusItem *(*originalStatusItem)(id, SEL, CGFloat);
static void HiddenStatusVisibility(id item, SEL selector, BOOL visible) {
    originalVisibility(item, selector, NO);
}
static NSStatusItem *HiddenStatusItem(id bar, SEL selector, CGFloat length) {
    // Return a real object so Wine can still update/destroy its tray view safely.
    NSStatusItem *item = originalStatusItem(bar, selector, length);
    item.visible = NO;
    fprintf(stderr,"[LWIdentity] original tray suppressed visible=%d\n",item.visible);
    return item;
}
static void (*originalWindowOrder)(id, SEL, NSWindowOrderingMode, NSInteger);
static void SetupWindowOrder(id window, SEL selector, NSWindowOrderingMode order, NSInteger relative) {
    originalWindowOrder(window, selector, NSWindowOut, relative);
}
__attribute__((constructor)) static void InstallDesktopIdentity(void) {
    const char *enabled = getenv("LW_WINE_DESKTOP_ENABLE");
    const char *title = getenv("LW_WINE_TARGET_TITLE");
    if (!enabled || strcmp(enabled,"1") || !title || strncmp(title,"LiveWallpaper-Wine-",19)) return;
    @autoreleasepool {
        const char *setup = getenv("LW_WINE_SETUP");
        if (setup && !strcmp(setup,"1")) {
            Method order = class_getInstanceMethod(NSWindow.class, @selector(orderWindow:relativeTo:));
            originalWindowOrder = (void *)method_setImplementation(order, (IMP)SetupWindowOrder);
        }
        Method method = class_getInstanceMethod(NSApplication.class, @selector(setActivationPolicy:));
        originalPolicy = (void *)method_setImplementation(method, (IMP)DesktopPolicy);
        Method visibility = class_getInstanceMethod(NSStatusItem.class, @selector(setVisible:));
        originalVisibility = (void *)method_setImplementation(visibility, (IMP)HiddenStatusVisibility);
        Method factory = class_getInstanceMethod(NSStatusBar.class, @selector(statusItemWithLength:));
        originalStatusItem = (void *)method_setImplementation(factory, (IMP)HiddenStatusItem);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (NSApp) [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
            fprintf(stderr,"[LWIdentity] desktop player uses accessory activation policy\n");
        });
    }
}
