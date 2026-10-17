#import <AppKit/AppKit.h>
#include <assert.h>
#include "../playback/wine_app_identity.m"
static NSApplicationActivationPolicy seen;
static BOOL RecordPolicy(id app, SEL selector, NSApplicationActivationPolicy policy) { seen=policy; return YES; }
static BOOL seenVisibility;
static void RecordVisibility(id item, SEL selector, BOOL visible) { seenVisibility=visible; }
static NSWindowOrderingMode seenOrder;
static NSInteger seenRelative;
static void RecordWindowOrder(id window, SEL selector, NSWindowOrderingMode order, NSInteger relative) {
    seenOrder=order; seenRelative=relative;
}
int main(void) {
    originalWindowOrder=RecordWindowOrder;
    SetupWindowOrder(nil,NULL,NSWindowAbove,42);
    assert(seenOrder==NSWindowOut && seenRelative==42);
    SetupWindowOrder(nil,NULL,NSWindowBelow,0);
    assert(seenOrder==NSWindowOut && seenRelative==0);
    originalVisibility=RecordVisibility;
    seenVisibility=YES; HiddenStatusVisibility(nil,NULL,YES); assert(!seenVisibility);
    HiddenStatusVisibility(nil,NULL,NO); assert(!seenVisibility);
    originalPolicy=RecordPolicy;
    assert(DesktopPolicy(nil,NULL,NSApplicationActivationPolicyRegular));
    assert(seen==NSApplicationActivationPolicyAccessory);
    assert(DesktopPolicy(nil,NULL,NSApplicationActivationPolicyAccessory));
    assert(seen==NSApplicationActivationPolicyAccessory);
    assert(DesktopPolicy(nil,NULL,NSApplicationActivationPolicyProhibited));
    assert(seen==NSApplicationActivationPolicyProhibited);
    puts("Desktop identity and setup window checks passed");
}
