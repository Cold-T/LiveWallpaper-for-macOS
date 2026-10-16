#pragma once
#import <Foundation/Foundation.h>

// Caller must have stopped this application-owned prefix's wineserver, including
// waiting for its registry flush. Editing one key offline avoids booting Wine
// with the old display scale before the first renderer process starts.
static BOOL LWSetWineRetina(NSString *prefix, BOOL enabled, NSError **error) {
  NSFileManager *fm = NSFileManager.defaultManager;
  NSString *registry = [prefix stringByAppendingPathComponent:@"user.reg"];
  NSString *root = prefix.stringByStandardizingPath.stringByResolvingSymlinksInPath;
  NSString *resolved = registry.stringByStandardizingPath.stringByResolvingSymlinksInPath;
  if (!prefix.isAbsolutePath || ![resolved hasPrefix:[root stringByAppendingString:@"/"]] ||
      [fm destinationOfSymbolicLinkAtPath:registry error:nil]) {
    if (error) *error = [NSError errorWithDomain:@"LiveWallpaperWinePrefix" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Wine registry must be a file inside the private prefix."}];
    return NO;
  }
  BOOL exists = [fm fileExistsAtPath:registry];
  NSString *original = exists ? [NSString stringWithContentsOfFile:registry encoding:NSUTF8StringEncoding error:error] : @"WINE REGISTRY Version 2\n#arch=win64\n";
  if (!original || ![original hasPrefix:@"WINE REGISTRY Version 2\n"]) {
    if (original && error) *error = [NSError errorWithDomain:@"LiveWallpaperWinePrefix" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Wine registry has an unsupported format; it was preserved."}];
    return NO;
  }
  NSString *section = @"[Software\\\\Wine\\\\Mac Driver]";
  NSString *desired = enabled ? @"\"RetinaMode\"=\"Y\"" : @"\"RetinaMode\"=\"N\"";
  NSMutableArray<NSString *> *lines = [NSMutableArray array];
  BOOL inSection = NO, foundSection = NO, written = NO, continuation = NO;
  for (NSString *line in [original componentsSeparatedByString:@"\n"]) {
    if (continuation) { continuation = [line hasSuffix:@"\\"]; continue; }
    if ([line hasPrefix:@"["]) {
      if (inSection && !written) { [lines addObject:desired]; written = YES; }
      NSRange closing = [line rangeOfString:@"]"];
      NSString *header = closing.location != NSNotFound ? [line substringToIndex:closing.location + 1] : line;
      inSection = [header caseInsensitiveCompare:section] == NSOrderedSame;
      if (inSection) foundSection = YES;
    }
    NSRange equals = [line rangeOfString:@"="];
    BOOL retinaValue = inSection && equals.location != NSNotFound &&
        [[line substringToIndex:equals.location] caseInsensitiveCompare:@"\"RetinaMode\""] == NSOrderedSame;
    if (retinaValue) {
      if (!written) { [lines addObject:desired]; written = YES; }
      continuation = [line hasSuffix:@"\\"];
    } else [lines addObject:line];
  }
  if (!foundSection) { [lines addObject:section]; [lines addObject:desired]; }
  else if (!written) [lines addObject:desired];
  NSString *updated = [lines componentsJoinedByString:@"\n"];
  if (![updated hasSuffix:@"\n"]) updated = [updated stringByAppendingString:@"\n"];
  if ([updated isEqualToString:original]) return YES;
  if (![updated writeToFile:registry atomically:YES encoding:NSUTF8StringEncoding error:error]) return NO;
  return [fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:registry error:error];
}
