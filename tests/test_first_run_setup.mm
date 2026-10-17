#import "../playback/setup/FirstRunSetup.mm"
#include <assert.h>
int main(void){@autoreleasepool{
  NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];NSError *error=nil;
  NSFileManager *fm=NSFileManager.defaultManager;assert([fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:&error]);
  assert(SetupRelative(@"assets/fonts/a.ttf"));assert(!SetupRelative(@"../engine"));assert(!SetupRelative(@"/engine"));assert(!SetupRelative(@"a/../b"));assert(!SetupRelative(@""));
  NSString *file=[root stringByAppendingPathComponent:@"test"];
  assert([@"known bytes" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:&error]);
  NSString *hash=SetupHash(file);assert(hash.length==64);assert(SetupVerify(root,@{@"test":hash},&error));
  assert(!SetupVerify(root,@{@"test":@"bad"},&error));assert(error);error=nil;
  assert([fm createSymbolicLinkAtPath:[root stringByAppendingPathComponent:@"link"] withDestinationPath:file error:&error]);
  assert(!SetupVerify(root,@{@"link":hash},&error));assert(!SetupVerify(root,@{@"../test":hash},&error));
  NSString *relativeLink=[root stringByAppendingPathComponent:@"runtime-link"];
  assert([fm createSymbolicLinkAtPath:relativeLink withDestinationPath:@"test" error:&error]);
  NSDictionary *runtime=@{@"runtime_files":@{@"test":hash},@"runtime_links":@{@"runtime-link":@"test"}};
  assert(SetupVerifyRuntime(root,runtime,&error));
  assert([fm removeItemAtPath:relativeLink error:&error]);
  assert([fm createSymbolicLinkAtPath:relativeLink withDestinationPath:@"../outside" error:&error]);
  assert(!SetupVerifyRuntime(root,runtime,&error));
  assert(!SetupVerifyRuntime(root,@{@"runtime_files":@{@"test":hash},@"runtime_links":@{@"runtime-link":@"../outside"}},&error));
  assert([fm removeItemAtPath:relativeLink error:&error]);
  assert(!SetupVerifyRuntime(root,runtime,&error));
  assert(!SetupManifest(root,&error));
  int lock=SetupLock(root,&error);assert(lock>=0);assert(SetupLock(root,&error)<0);flock(lock,LOCK_UN);close(lock);
  assert(SetupRun(@"/usr/bin/true",@[],@{},root,[root stringByAppendingPathComponent:@"test.log"],2,&error));
  assert(!SetupRun(@"/usr/bin/false",@[],@{},root,[root stringByAppendingPathComponent:@"test.log"],2,&error));
  assert(SetupRun(@"/usr/bin/false",@[],@{},root,[root stringByAppendingPathComponent:@"test.log"],2,&error,YES));
  // Schema 2 assembles a pinned, pre-cached vendor archive plus a local overlay.
  NSString *vendor=[root stringByAppendingPathComponent:@"vendor"];
  NSString *overlay=[root stringByAppendingPathComponent:@"overlay"];
  NSString *cache=[root stringByAppendingPathComponent:@"downloads"];
  for(NSString *dir in @[vendor,overlay,cache])assert([fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error]);
  assert([@"vendor bytes" writeToFile:[vendor stringByAppendingPathComponent:@"binary"] atomically:YES encoding:NSUTF8StringEncoding error:&error]);
  assert([@"overlay bytes" writeToFile:[overlay stringByAppendingPathComponent:@"bridge"] atomically:YES encoding:NSUTF8StringEncoding error:&error]);
  NSString *vendorTar=[root stringByAppendingPathComponent:@"vendor.tar"];
  NSString *overlayTar=[root stringByAppendingPathComponent:@"RuntimeOverlay.tar.gz"];
  assert(SetupRun(@"/usr/bin/tar",@[@"-cf",vendorTar,@"-C",vendor,@"binary"],@{},root,[root stringByAppendingPathComponent:@"tar.log"],10,&error));
  assert(SetupRun(@"/usr/bin/tar",@[@"-czf",overlayTar,@"-C",overlay,@"bridge"],@{},root,[root stringByAppendingPathComponent:@"tar.log"],10,&error));
  NSString *vendorHash=SetupHash(vendorTar),*overlayHash=SetupHash(overlayTar),*vendorFileHash=SetupHash([vendor stringByAppendingPathComponent:@"binary"]),*bridgeHash=SetupHash([overlay stringByAppendingPathComponent:@"bridge"]);
  assert([fm moveItemAtPath:vendorTar toPath:[cache stringByAppendingPathComponent:[vendorHash stringByAppendingString:@".tar.xz"]] error:&error]);
  NSMutableDictionary *download=[@{@"id":@"vendor",@"url":@"https://github.com/example/runtime/releases/download/v1/vendor.tar.xz",@"sha256":vendorHash,@"bytes":[fm attributesOfItemAtPath:[cache stringByAppendingPathComponent:[vendorHash stringByAppendingString:@".tar.xz"]] error:nil][NSFileSize]} mutableCopy];
  NSMutableDictionary *manifest=[@{@"schema":@2,@"archive_sha256":overlayHash,@"engine_sha256":hash,@"requires_free_bytes":@0,@"downloads":@[download],@"runtime_files":@{@"wine/binary":vendorFileHash,@"bridge":bridgeHash},@"runtime_links":@{@"alias":@"wine/binary"},@"source_files":@{@"wine/binary":@{@"archive":@"vendor",@"path":@"binary"}},@"overlay_files":@{@"bridge":bridgeHash},@"engine_files":@{@"engine.exe":hash}} mutableCopy];
  NSString *manifestPath=[root stringByAppendingPathComponent:@"SetupRuntime.json"];
  assert([[NSJSONSerialization dataWithJSONObject:manifest options:0 error:&error] writeToFile:manifestPath atomically:YES]);
  assert(SetupManifest(root,&error));
  NSString *assembled=SetupComponents(root,root,manifest,^(NSString *,double){},&error);
  assert(assembled && SetupVerifyRuntime(assembled,manifest,&error));
  assert([SetupComponents(root,root,manifest,^(NSString *,double){},&error) isEqual:assembled]);
  download[@"url"]=@"http://github.com/example/runtime/releases/download/v1/vendor.tar.xz";
  assert([[NSJSONSerialization dataWithJSONObject:manifest options:0 error:&error] writeToFile:manifestPath atomically:YES]);
  assert(!SetupManifest(root,&error));
  [fm removeItemAtPath:root error:nil];puts("Setup integrity, path, locking and process result checks passed");
}}
