#import <Foundation/Foundation.h>
#import "../playback/WineRuntimeEnvironment.h"
#include <assert.h>

// Pure environment assembly only. No supervisor, Wine, GUI or subprocess starts.
int main(void) {
  @autoreleasepool {
    NSString *runtime = @"/private/tmp/Selected Runtime";
    NSMutableDictionary *env = [@{@"WINEDLLPATH":@"/other/wine", @"WINESERVER":@"/other/server",
                                  @"WINELOADERNOEXEC":@"0", @"PATH":@"/usr/bin:/bin", @"UNRELATED":@"kept"} mutableCopy];
    LWConfigureWineRuntimeEnvironment(env, runtime);
    assert([env[@"SikarugirAppWine11"] isEqualToString:@"1"]);
    assert([env[@"WINELOADERNOEXEC"] isEqualToString:@"1"]);
    assert([env[@"WINEDLLPATH"] isEqualToString:@"/private/tmp/Selected Runtime/wine/lib/wine"]);
    assert([env[@"WINESERVER"] isEqualToString:@"/private/tmp/Selected Runtime/wine/bin/wineserver"]);
    assert([env[@"PATH"] isEqualToString:@"/private/tmp/Selected Runtime/wine/bin:/usr/bin:/bin"]);
    assert([env[@"UNRELATED"] isEqualToString:@"kept"]);
    [env removeObjectForKey:@"PATH"];
    LWConfigureWineRuntimeEnvironment(env, runtime);
    assert([env[@"PATH"] hasSuffix:@":/usr/bin:/bin"]);
    env[@"PATH"] = @"";
    LWConfigureWineRuntimeEnvironment(env, runtime);
    assert([env[@"PATH"] isEqualToString:@"/private/tmp/Selected Runtime/wine/bin"]);
    puts("Wine launch environment checks passed; no processes launched.");
  }
  return 0;
}
