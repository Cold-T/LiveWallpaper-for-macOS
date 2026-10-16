#pragma once
#import <Foundation/Foundation.h>
#import "WineFonts.h"
#import "WineQuality.h"
#include <stdlib.h>

// Apply only to the app-owned runtime/prefix. Do not modify Windows binaries
// or Workshop resources. Existing user-supplied font files are preserved.
static BOOL LWPrepareWineCompatibility(NSString *runtime, NSString *prefix, NSError **error) {
  NSString *engine = [runtime stringByAppendingPathComponent:@"engine"];
  NSString *configPath = [engine stringByAppendingPathComponent:@"config.json"];
  NSData *data = [NSData dataWithContentsOfFile:configPath];
  id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:error] : [NSMutableDictionary dictionary];
  if (![parsed isKindOfClass:NSMutableDictionary.class]) return NO;
  const char *qualityName = getenv("LIVEWALLPAPER_WINE_QUALITY");
  NSDictionary *quality = qualityName && *qualityName ? LWShippedQualityPreset([NSString stringWithUTF8String:qualityName]) : nil;
  if (qualityName && *qualityName && !quality) {
    if (error) *error = [NSError errorWithDomain:@"LiveWallpaperWine" code:5 userInfo:@{NSLocalizedDescriptionKey:@"Unknown Wallpaper Engine quality preset."}];
    return NO;
  }
  NSMutableDictionary *config = parsed;
  BOOL changed = NO;
  NSMutableArray *profiles = [NSMutableArray array];
  for (id value in config.allValues) {
    if ([value isKindOfClass:NSMutableDictionary.class] && [value[@"general"] isKindOfClass:NSMutableDictionary.class]) [profiles addObject:value];
  }
  if (!profiles.count) {
    NSMutableDictionary *profile = [NSMutableDictionary dictionaryWithDictionary:@{@"general":[NSMutableDictionary dictionary]}];
    config[NSUserName()] = profile; [profiles addObject:profile]; changed = YES;
  }
  NSDictionary *policy = @{@"mediaintegration":@NO, @"uihardwareacceleration":@NO,
                           @"cefcommandline":@"--disable-gpu --disable-gpu-compositing", @"hasshownwelcomedialog":@YES};
  for (NSMutableDictionary *profile in profiles) {
    NSMutableDictionary *general = profile[@"general"];
    NSMutableDictionary *user = [general[@"user"] isKindOfClass:NSMutableDictionary.class] ? general[@"user"] : [NSMutableDictionary dictionary];
    general[@"user"] = user;
    for (NSString *key in policy) if (![user[key] isEqual:policy[key]]) { user[key] = policy[key]; changed = YES; }
    // Silent first launch skips the wizard; fill only absent settings with its
    // actual medium preset. Preserve existing choices unless explicitly asked.
    NSDictionary *defaults = LWShippedQualityPreset(@"medium");
    for (NSString *key in defaults) if (!user[key]) { user[key] = defaults[key]; changed = YES; }
    for (NSString *key in quality) if (![user[key] isEqual:quality[key]]) { user[key] = quality[key]; changed = YES; }
  }
  if (changed) {
    NSData *updated = [NSJSONSerialization dataWithJSONObject:config options:NSJSONWritingPrettyPrinted error:error];
    if (!updated || ![updated writeToFile:configPath options:NSDataWritingAtomic error:error]) return NO;
  }
  return LWPrepareWineFonts(runtime, prefix, error);
}
