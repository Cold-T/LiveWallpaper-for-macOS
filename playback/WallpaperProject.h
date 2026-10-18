#pragma once
#import <Foundation/Foundation.h>

// Keep the v1.1.1 flat library, with whole Workshop directories as new entries.
static NSString *LWProjectJSON(NSString *path) {
  BOOL directory = NO;
  if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory]) return nil;
  NSString *json = directory ? [path stringByAppendingPathComponent:@"project.json"] : path;
  if (![json.lastPathComponent.lowercaseString isEqualToString:@"project.json"]) return nil;
  NSData *data = [NSData dataWithContentsOfFile:json];
  id project = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  if (![project isKindOfClass:NSDictionary.class]) return nil;
  NSString *type = [project[@"type"] isKindOfClass:NSString.class] ? [project[@"type"] lowercaseString] : @"";
  // Executable/application wallpapers are not automatically launched.
  return [@[@"scene", @"web", @"video"] containsObject:type] ? json : nil;
}
// Video projects contain a media file; render it directly through AVFoundation.
static NSString *LWNativeVideoProjectFile(NSString *json, NSError **error) {
  NSDictionary *project = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:json] ?: NSData.data options:0 error:nil];
  NSString *type = [project[@"type"] isKindOfClass:NSString.class] ? [project[@"type"] lowercaseString] : @"";
  if (![type isEqualToString:@"video"]) return nil;
  NSString *file = [project[@"file"] isKindOfClass:NSString.class] ? project[@"file"] : @"";
  file = [file stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
  NSString *root = json.stringByResolvingSymlinksInPath.stringByDeletingLastPathComponent;
  NSString *target = [[root stringByAppendingPathComponent:file] stringByStandardizingPath].stringByResolvingSymlinksInPath;
  BOOL directory = NO;
  if (!file.length || file.isAbsolutePath || [file containsString:@":"] ||
      ![target hasPrefix:[root stringByAppendingString:@"/"]] ||
      ![NSFileManager.defaultManager fileExistsAtPath:target isDirectory:&directory] || directory) {
    if (error) *error = [NSError errorWithDomain:@"LiveWallpaperVideo" code:1 userInfo:@{NSLocalizedDescriptionKey:@"The video referenced by this project is missing or outside its folder. / 项目引用的视频缺失或位于项目文件夹之外。"}];
    return nil;
  }
  return target;
}
static BOOL LWPlayablePath(NSString *path) {
  return LWProjectJSON(path) != nil || [@[@"mp4", @"mov"] containsObject:path.pathExtension.lowercaseString];
}
