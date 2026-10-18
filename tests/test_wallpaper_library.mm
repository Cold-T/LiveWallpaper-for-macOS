#import "../playback/WallpaperLibrary.h"
#include <assert.h>
static void makeProject(NSString *root,NSString *name,NSString *type){
  NSString *dir=[root stringByAppendingPathComponent:name];assert([NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil]);
  NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"type":type,@"file":@"wallpaper.mp4"} options:0 error:nil];assert([data writeToFile:[dir stringByAppendingPathComponent:@"project.json"] atomically:YES]);
}
int main(){@autoreleasepool{
 NSFileManager *fm=NSFileManager.defaultManager;NSString *base=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];NSError *error=nil;
 NSString *library=LWRestoreDownloadedWallpaperLibrary(base,&error);assert(library && !error);assert(!LWLibraryHasPlayableItems(library));
 NSString *downloads=[base stringByAppendingPathComponent:@"SteamWorkshop/steamapps/workshop/content/431960"];
 makeProject(downloads,@"123",@"video");makeProject(downloads,@"456",@"scene");makeProject(downloads,@"789",@"application");
 assert(LWRestoreDownloadedWallpaperLibrary(base,&error));
 assert(LWProjectJSON([library stringByAppendingPathComponent:@"123.weproject"]));assert(LWProjectJSON([library stringByAppendingPathComponent:@"456.weproject"]));assert(![fm fileExistsAtPath:[library stringByAppendingPathComponent:@"789.weproject"]]);assert(LWLibraryHasPlayableItems(library));
 assert(LWRestoreDownloadedWallpaperLibrary(base,&error));assert([[fm contentsOfDirectoryAtPath:library error:nil] count]==2);
 // Recovering a deleted library recreates links while retaining original projects.
 assert([fm removeItemAtPath:library error:nil]);assert(LWRestoreDownloadedWallpaperLibrary(base,&error));assert([fm fileExistsAtPath:[downloads stringByAppendingPathComponent:@"123/project.json"]]);
 // Existing entries belong to the user and are preserved.
 NSString *entry=[library stringByAppendingPathComponent:@"123.weproject"];assert([fm removeItemAtPath:entry error:nil]);assert([[@"keep" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:entry atomically:YES]);assert(LWRestoreDownloadedWallpaperLibrary(base,&error));assert([[NSString stringWithContentsOfFile:entry encoding:NSUTF8StringEncoding error:nil] isEqualToString:@"keep"]);
 [fm removeItemAtPath:base error:nil];NSLog(@"PASS retained download recovery and persistent library");
}}
