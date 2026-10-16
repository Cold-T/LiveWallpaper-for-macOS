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
static BOOL LWPlayablePath(NSString *path) {
  return LWProjectJSON(path) != nil || [@[@"mp4", @"mov"] containsObject:path.pathExtension.lowercaseString];
}
