#pragma once
#import <Foundation/Foundation.h>

// Engine 2.8.42 opens these filenames in CSIDL_FONTS directly. Font family
// substitution cannot repair that path. Reuse installed files on this Mac;
// never bundle, download, or redistribute proprietary font files here.
static NSDictionary<NSString *, NSArray<NSString *> *> *LWWineFontFilenames(void) {
  return @{@"arial.ttf":@[@"arial.ttf", @"Arial.ttf"],
           @"calibri.ttf":@[@"Calibri.ttf", @"calibri.ttf"],
           @"cambria.ttc":@[@"Cambria.ttc", @"cambria.ttc"],
           @"comic.ttf":@[@"comic.ttf", @"Comic Sans MS.ttf", @"ComicSansMS.ttf"],
           @"consola.ttf":@[@"Consola.ttf", @"consola.ttf"],
           @"micross.ttf":@[@"micross.ttf"],
           @"segoeui.ttf":@[@"segoeui.ttf"],
           @"verdana.ttf":@[@"Verdana.ttf", @"verdana.ttf"]};
}

static BOOL LWWineFontsError(NSError **error, NSString *message) {
  if (error) *error = [NSError errorWithDomain:@"LiveWallpaperWineFonts" code:1
      userInfo:@{NSLocalizedDescriptionKey:message}];
  return NO;
}

// Roots are explicit, nonrecursive source directories. Injection makes path
// validation testable without reading or altering installed fonts.
static BOOL LWPrepareWineFontsWithRoots(NSString *runtime, NSString *prefix,
                                        NSArray<NSString *> *roots, NSError **error) {
  NSFileManager *fm = NSFileManager.defaultManager;
  NSString *resolvedPrefix = prefix.stringByStandardizingPath.stringByResolvingSymlinksInPath;
  NSString *fonts = [prefix stringByAppendingPathComponent:@"drive_c/windows/Fonts"];
  NSString *resolvedFonts = fonts.stringByStandardizingPath.stringByResolvingSymlinksInPath;
  if (![prefix isAbsolutePath] || ![runtime isAbsolutePath] ||
      ![resolvedFonts hasPrefix:[resolvedPrefix stringByAppendingString:@"/"]])
    return LWWineFontsError(error, @"Wine font directory escapes the private prefix.");
  for (NSString *root in roots)
    if (![root isAbsolutePath]) return LWWineFontsError(error, @"Font source root must be absolute.");
  if (![fm createDirectoryAtPath:fonts withIntermediateDirectories:YES attributes:nil error:error]) return NO;
  NSDictionary *mapping = LWWineFontFilenames();
  for (NSString *filename in [mapping.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
    NSString *target = [fonts stringByAppendingPathComponent:filename];
    // A user-provided file or symlink (including dangling links) always wins.
    if ([fm fileExistsAtPath:target] || [fm destinationOfSymbolicLinkAtPath:target error:nil]) continue;
    NSString *selected = nil;
    for (NSString *root in roots) {
      NSString *resolvedRoot = root.stringByStandardizingPath.stringByResolvingSymlinksInPath;
      for (NSString *candidate in mapping[filename]) {
        NSString *source = [root stringByAppendingPathComponent:candidate];
        BOOL directory = NO;
        if (![fm fileExistsAtPath:source isDirectory:&directory] || directory) continue;
        NSString *resolvedSource = source.stringByStandardizingPath.stringByResolvingSymlinksInPath;
        // Do not follow a font-name symlink into an unrelated document tree.
        if (![resolvedSource hasPrefix:[resolvedRoot stringByAppendingString:@"/"]]) continue;
        selected = resolvedSource; break;
      }
      if (selected) break;
    }
    if (selected) {
      if (![fm createSymbolicLinkAtPath:target withDestinationPath:selected error:error]) return NO;
    } else if ([filename isEqualToString:@"consola.ttf"]) {
      // Last-resort compatibility only; Roboto Mono is not glyph-identical.
      NSString *source = [runtime stringByAppendingPathComponent:@"engine/assets/fonts/RobotoMono-Regular.ttf"];
      NSString *resolvedRuntime = runtime.stringByStandardizingPath.stringByResolvingSymlinksInPath;
      if (![source.stringByResolvingSymlinksInPath hasPrefix:[resolvedRuntime stringByAppendingString:@"/"]])
        return LWWineFontsError(error, @"Fallback font escapes the selected runtime.");
      if (![fm copyItemAtPath:source toPath:target error:error]) return NO;
    }
  }
  return YES;
}

static BOOL LWPrepareWineFonts(NSString *runtime, NSString *prefix, NSError **error) {
  NSArray *roots = @[@"/Applications/Microsoft Word.app/Contents/Resources/DFonts",
                    @"/Applications/Microsoft Excel.app/Contents/Resources/DFonts",
                    @"/Applications/Microsoft PowerPoint.app/Contents/Resources/DFonts",
                    @"/Library/Fonts", [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Fonts"],
                    @"/System/Library/Fonts/Supplemental"];
  return LWPrepareWineFontsWithRoots(runtime, prefix, roots, error);
}
