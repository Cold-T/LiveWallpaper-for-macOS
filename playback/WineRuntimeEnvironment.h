#pragma once
#import <Foundation/Foundation.h>

// Derive module/server paths from the selected runtime instead of inheriting
// another Wine installation. prepare_wine_runtime.py records the same contract.
static void LWConfigureWineRuntimeEnvironment(NSMutableDictionary *env, NSString *runtime) {
  NSString *bin = [runtime stringByAppendingPathComponent:@"wine/bin"];
  env[@"SikarugirAppWine11"] = @"1";
  env[@"WINELOADERNOEXEC"] = @"1";
  env[@"WINEDLLPATH"] = [runtime stringByAppendingPathComponent:@"wine/lib/wine"];
  env[@"WINESERVER"] = [bin stringByAppendingPathComponent:@"wineserver"];
  NSString *path = [env[@"PATH"] isKindOfClass:NSString.class] ? env[@"PATH"] : @"/usr/bin:/bin";
  env[@"PATH"] = path.length ? [bin stringByAppendingFormat:@":%@", path] : bin;
}
