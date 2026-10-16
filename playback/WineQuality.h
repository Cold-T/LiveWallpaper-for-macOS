#pragma once
#import <Foundation/Foundation.h>

// Wallpaper Engine 2.8.42 shipped UI, utils.getQualityPreset(). The first-run
// wizard selects medium. These are comparison presets, not guessed GPU defaults.
static NSDictionary *LWShippedQualityPreset(NSString *name) {
  NSDictionary *profiles = @{
    @"low":@{@"msaa":@"none", @"resolution":@"full", @"fps":@10, @"postprocessing":@"disabled", @"reflection":@NO, @"shadows":@"low", @"volumetrics":@"low"},
    @"medium":@{@"msaa":@"none", @"resolution":@"full", @"fps":@15, @"postprocessing":@"enabled", @"reflection":@YES, @"shadows":@"medium", @"volumetrics":@"medium"},
    @"high":@{@"msaa":@"x2", @"resolution":@"full", @"fps":@25, @"postprocessing":@"enabled", @"reflection":@YES, @"shadows":@"high", @"volumetrics":@"high"},
    @"ultra":@{@"msaa":@"x2", @"resolution":@"full", @"fps":@30, @"postprocessing":@"ultra", @"reflection":@YES, @"shadows":@"ultra", @"volumetrics":@"ultra"}
  };
  return profiles[name];
}
