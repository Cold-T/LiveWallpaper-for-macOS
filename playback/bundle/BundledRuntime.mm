#import "BundledRuntime.h"
#import <Cocoa/Cocoa.h>
#import <CommonCrypto/CommonDigest.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>

static NSString *digest(NSString *path) {
  NSInputStream *in = [NSInputStream inputStreamWithFileAtPath:path];
  [in open]; CC_SHA256_CTX ctx; CC_SHA256_Init(&ctx);
  uint8_t buf[262144]; NSInteger n;
  while ((n = [in read:buf maxLength:sizeof(buf)]) > 0) CC_SHA256_Update(&ctx, buf, (CC_LONG)n);
  [in close]; if (n < 0) return nil;
  unsigned char out[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(out, &ctx);
  NSMutableString *s = [NSMutableString string];
  for (unsigned i=0;i<sizeof(out);i++) [s appendFormat:@"%02x",out[i]];
  return s;
}
static BOOL verifyFiles(NSString *root, NSDictionary *files) {
  for (NSString *path in files) {
    if (![digest([root stringByAppendingPathComponent:path]) isEqual:files[path]]) return NO;
  }
  return YES;
}
static NSString *prepare(NSString *resources, NSDictionary *meta, NSString **failure) {
  NSFileManager *fm=NSFileManager.defaultManager;
  NSString *support=[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"LiveWallpaper-Wine/BundledRuntimes"];
  NSError *error=nil;
  if (![fm createDirectoryAtPath:support withIntermediateDirectories:YES attributes:nil error:&error]) { *failure=error.localizedDescription; return nil; }
  NSString *key=meta[@"archive_sha256"];
  if (key.length!=64) { *failure=@"Invalid bundled runtime receipt.";return nil; }
  NSString *dest=[support stringByAppendingPathComponent:key];
  int lock=open([[support stringByAppendingPathComponent:@"install.lock"] fileSystemRepresentation],O_CREAT|O_RDWR|O_NOFOLLOW,0600);
  if (lock<0 || flock(lock,LOCK_EX)!=0) { if(lock>=0)close(lock); *failure=@"Cannot lock runtime installation.";return nil; }
  NSString *result=nil;
  @try {
    NSString *stamp=[dest stringByAppendingPathComponent:@".bundle-complete"];
    if ([[NSString stringWithContentsOfFile:stamp encoding:NSUTF8StringEncoding error:nil] isEqual:key] && verifyFiles(dest,meta[@"critical_files"])) {result=dest;}
    else if ([fm fileExistsAtPath:dest]) { *failure=@"The installed bundled runtime failed verification. Remove only this version's runtime folder and reopen the app."; }
    else {
      NSString *archive=[resources stringByAppendingPathComponent:@"PlaybackRuntime.tar.gz"];
      if (![digest(archive) isEqual:key]) { *failure=@"Bundled runtime archive is damaged. Extract the application ZIP again."; }
      else {
        NSString *stage=[support stringByAppendingPathComponent:[NSString stringWithFormat:@".install-%@",NSUUID.UUID.UUIDString]];
        if (![fm createDirectoryAtPath:stage withIntermediateDirectories:NO attributes:nil error:&error]) *failure=error.localizedDescription;
        else {
          @try {
            NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/tar"];
            task.arguments=@[@"-xzf",archive,@"-C",stage];
            NSMutableDictionary *env=[NSProcessInfo.processInfo.environment mutableCopy];env[@"COPYFILE_DISABLE"]=@"1";task.environment=env;
            if (![task launchAndReturnError:&error]) *failure=error.localizedDescription;
            else { [task waitUntilExit];
              if (task.terminationStatus!=0 || !verifyFiles(stage,meta[@"critical_files"])) *failure=@"Runtime extraction or file verification failed.";
              else if (![key writeToFile:[stage stringByAppendingPathComponent:@".bundle-complete"] atomically:YES encoding:NSUTF8StringEncoding error:&error]) *failure=error.localizedDescription;
              else if (![fm moveItemAtPath:stage toPath:dest error:&error]) *failure=error.localizedDescription;
              else result=dest;
            }
          } @catch (NSException *e) { *failure=e.reason; }
          if (!result) [fm removeItemAtPath:stage error:nil];
        }
      }
    }
  } @finally {flock(lock,LOCK_UN);close(lock);}
  return result;
}
BOOL LWPrepareBundledRuntime(void) { @autoreleasepool {
  NSBundle *bundle=NSBundle.mainBundle;
  NSString *resources=bundle.resourcePath;
  if (![[NSFileManager defaultManager] fileExistsAtPath:[resources stringByAppendingPathComponent:@"BundledRuntime.json"]]) return YES;
  NSDictionary *meta=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[resources stringByAppendingPathComponent:@"BundledRuntime.json"]] options:0 error:nil];
  if (![meta[@"critical_files"] isKindOfClass:NSDictionary.class] || ![meta[@"archive_sha256"] isKindOfClass:NSString.class]) {fprintf(stderr,"Missing bundled runtime metadata\n");return NO;}
  // A prepared runtime must not create NSApplication or a temporary window
  // before SwiftUI installs the real app delegate and menu bar item.
  NSString *support=[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"LiveWallpaper-Wine/BundledRuntimes"];
  NSString *cached=[support stringByAppendingPathComponent:meta[@"archive_sha256"]];
  if ([NSFileManager.defaultManager fileExistsAtPath:[cached stringByAppendingPathComponent:@".bundle-complete"]]) {
    NSString *error=nil; NSString *ready=prepare(resources,meta,&error);
    if (ready) { setenv("LIVEWALLPAPER_WINE_RUNTIME",ready.fileSystemRepresentation,1); return YES; }
  }
  NSWindow *window=nil;
  [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
  window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,460,110) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.title=@"Livewallpaper for macOS";
  NSTextField *label=[NSTextField labelWithString:@"正在准备播放环境，首次启动需要解包，请稍候…"];
  label.frame=NSMakeRect(20,55,420,30);[window.contentView addSubview:label];
  NSProgressIndicator *progress=[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20,25,420,16)];progress.indeterminate=YES;[progress startAnimation:nil];[window.contentView addSubview:progress];
  [window center];[window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
  __block NSString *runtime=nil,*failure=nil;__block BOOL done=NO;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
    NSString *error=nil;NSString *path=prepare(resources,meta,&error);
    dispatch_async(dispatch_get_main_queue(),^{runtime=path;failure=error;done=YES;});
  });
  while(!done) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  [window orderOut:nil];
  if (!runtime) {
    fprintf(stderr,"%s\n",failure.UTF8String);
    NSAlert *alert=[NSAlert new];alert.messageText=@"播放环境准备失败";alert.informativeText=failure?:@"Unknown error";[alert runModal];
    return NO;
  }
  setenv("LIVEWALLPAPER_WINE_RUNTIME",runtime.fileSystemRepresentation,1);
  return YES;
}}
