#pragma once
#import "WallpaperProject.h"

// Library entries must survive cache cleanup and point at the retained downloads.
static NSString *LWRestoreDownloadedWallpaperLibrary(NSString *support, NSError **error) {
  NSFileManager *fm = NSFileManager.defaultManager;
  NSString *library = [support stringByAppendingPathComponent:@"ImportedWallpapers"];
  if (![fm createDirectoryAtPath:library withIntermediateDirectories:YES attributes:nil error:error]) return nil;
  NSString *downloads = [support stringByAppendingPathComponent:@"SteamWorkshop/steamapps/workshop/content/431960"];
  BOOL directory = NO;
  if (![fm fileExistsAtPath:downloads isDirectory:&directory] || !directory) return library;
  NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:downloads error:error];
  if (!items) return nil;
  NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
  for (NSString *item in items) {
    if (!item.length || [item rangeOfCharacterFromSet:nonDigits].location != NSNotFound) continue;
    NSString *project = [downloads stringByAppendingPathComponent:item];
    if (!LWProjectJSON(project)) continue;
    NSString *entry = [library stringByAppendingPathComponent:[item stringByAppendingString:@".weproject"]];
    // Keep existing entries, including user-managed links.
    if ([fm attributesOfItemAtPath:entry error:nil]) continue;
    if (![fm createSymbolicLinkAtPath:entry withDestinationPath:project error:error]) return nil;
  }
  return library;
}

static BOOL LWLibraryHasPlayableItems(NSString *path) {
  for (NSString *item in [NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:nil]) {
    if (LWPlayablePath([path stringByAppendingPathComponent:item])) return YES;
  }
  return NO;
}
