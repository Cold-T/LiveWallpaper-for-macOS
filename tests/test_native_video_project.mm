#import "../playback/WallpaperProject.h"
#include <assert.h>
static void project(NSString *path, NSString *type, NSString *file){
  NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"type":type,@"file":file} options:0 error:nil];assert([data writeToFile:path atomically:YES]);
}
int main(){@autoreleasepool{
  NSFileManager *fm=NSFileManager.defaultManager;NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  assert([fm createDirectoryAtPath:[root stringByAppendingPathComponent:@"assets"] withIntermediateDirectories:YES attributes:nil error:nil]);
  NSString *media=[root stringByAppendingPathComponent:@"assets/壁纸 clip.mp4"],*json=[root stringByAppendingPathComponent:@"project.json"];
  assert([[@"fixture" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:media atomically:YES]);
  project(json,@"video",@"assets\\壁纸 clip.mp4");NSError *error=nil;
  assert([LWNativeVideoProjectFile(json,&error) isEqual:media]);assert(!error);assert(LWProjectJSON(root));
  NSString *alias=[root stringByAppendingString:@".weproject"];assert([fm createSymbolicLinkAtPath:alias withDestinationPath:root error:nil]);
  assert([LWNativeVideoProjectFile(LWProjectJSON(alias),&error) isEqual:media]);
  for(NSString *file in @[@"missing.mp4",@"../escape.mp4",@"/tmp/external.mp4",@"C:\\external.mp4",@"assets"]){
    project(json,@"video",file);error=nil;assert(!LWNativeVideoProjectFile(json,&error));assert(error);
  }
  for(NSString *type in @[@"scene",@"web"]){project(json,type,@"scene.pkg");error=nil;assert(!LWNativeVideoProjectFile(json,&error));assert(!error);assert(LWProjectJSON(root));}
  [fm removeItemAtPath:alias error:nil];[fm removeItemAtPath:root error:nil];
  NSLog(@"Native Video project resolution passed");
}}
