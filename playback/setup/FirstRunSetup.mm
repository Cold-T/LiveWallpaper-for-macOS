#import "FirstRunSetup.h"
#import "../WineCompatibility.h"
#import "../WinePrefix.h"
#import "../WineMediaModules.h"
#import "../WineRuntimeEnvironment.h"
#import "../WineTaskWait.h"
#import <CommonCrypto/CommonDigest.h>
#include <sys/file.h>

static NSString *SetupHash(NSString *path) {
  NSInputStream *stream=[NSInputStream inputStreamWithFileAtPath:path]; [stream open];
  CC_SHA256_CTX ctx; CC_SHA256_Init(&ctx); uint8_t buffer[262144]; NSInteger count;
  while ((count=[stream read:buffer maxLength:sizeof(buffer)])>0) CC_SHA256_Update(&ctx,buffer,(CC_LONG)count);
  [stream close]; if(count<0)return nil; unsigned char hash[32];CC_SHA256_Final(hash,&ctx);
  NSMutableString *result=[NSMutableString string];for(unsigned i=0;i<32;i++)[result appendFormat:@"%02x",hash[i]];return result;
}
static BOOL SetupFail(NSError **error, NSString *message) {
  if(error)*error=[NSError errorWithDomain:@"LiveWallpaperSetup" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];return NO;
}
static BOOL SetupRelative(NSString *path) {
  if(![path isKindOfClass:NSString.class]||!path.length||path.isAbsolutePath)return NO;
  for(NSString *part in path.pathComponents)if([part isEqual:@".."]||[part isEqual:@"."])return NO;
  return YES;
}
static NSString *SetupRoot(void) {
  return [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"LiveWallpaper-Wine/Setup"];
}
static NSDictionary *SetupManifest(NSString *resources, NSError **error) {
  NSData *data=[NSData dataWithContentsOfFile:[resources stringByAppendingPathComponent:@"SetupRuntime.json"] options:0 error:error];
  if(!data){SetupFail(error,@"This app does not include the setup runtime. Open the full setup edition. / 请使用包含运行时的完整安装包。");return nil;}
  id meta=[NSJSONSerialization JSONObjectWithData:data options:0 error:error];
  if(![meta isKindOfClass:NSDictionary.class]||![@[@1,@2] containsObject:meta[@"schema"]]){SetupFail(error,@"Invalid setup manifest.");return nil;}
  for(NSString *key in @[@"archive_sha256",@"engine_sha256"]){id hash=meta[key];if(![hash isKindOfClass:NSString.class]||[hash length]!=64||[hash rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location!=NSNotFound){SetupFail(error,@"Invalid setup hash.");return nil;}}
  for(NSString *key in @[@"runtime_files",@"engine_files",@"runtime_links"]){if(![meta[key] isKindOfClass:NSDictionary.class]){SetupFail(error,@"Invalid component list.");return nil;}for(NSString *path in meta[key])if(!SetupRelative(path)){SetupFail(error,@"Invalid component path.");return nil;}}
  if(![meta[@"engine_files"] count]||![meta[@"runtime_files"] count]){SetupFail(error,@"Empty component list.");return nil;}
  if ([meta[@"schema"] integerValue] == 2) {
    if (![meta[@"downloads"] isKindOfClass:NSArray.class] || ![meta[@"downloads"] count] ||
        ![meta[@"source_files"] isKindOfClass:NSDictionary.class] || ![meta[@"overlay_files"] isKindOfClass:NSDictionary.class]) {
      SetupFail(error,@"Invalid download manifest."); return nil;
    }
    NSMutableSet *ids=[NSMutableSet set];
    for (id item in meta[@"downloads"]) {
      if (![item isKindOfClass:NSDictionary.class]) { SetupFail(error,@"Invalid download entry."); return nil; }
      NSString *identifier=item[@"id"], *hash=item[@"sha256"];
      NSURL *url=[item[@"url"] isKindOfClass:NSString.class]?[NSURL URLWithString:item[@"url"]]:nil;
      if (!SetupRelative(identifier) || [identifier containsString:@"/"] || [ids containsObject:identifier] ||
          ![hash isKindOfClass:NSString.class] || hash.length!=64 ||
          [hash rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location!=NSNotFound ||
          ![url.scheme isEqual:@"https"] || ![url.host isEqual:@"github.com"] ||
          ![url.path containsString:@"/releases/download/"] || url.user || url.password ||
          ![item[@"bytes"] isKindOfClass:NSNumber.class] || [item[@"bytes"] longLongValue]<=0) {
        SetupFail(error,@"Invalid pinned download."); return nil;
      }
      [ids addObject:identifier];
    }
    for (NSString *relative in meta[@"source_files"]) {
      id entry=meta[@"source_files"][relative];
      if (!SetupRelative(relative) || !meta[@"runtime_files"][relative] ||
          ![entry isKindOfClass:NSDictionary.class] || ![ids containsObject:entry[@"archive"]] || !SetupRelative(entry[@"path"])) {
        SetupFail(error,@"Invalid source component."); return nil;
      }
    }
    for (NSString *relative in meta[@"overlay_files"]) {
      if (!SetupRelative(relative) || ![meta[@"overlay_files"][relative] isEqual:meta[@"runtime_files"][relative]]) {
        SetupFail(error,@"Invalid overlay component."); return nil;
      }
    }
    for (NSString *relative in meta[@"runtime_files"]) {
      if (!meta[@"source_files"][relative] && !meta[@"overlay_files"][relative]) {
        SetupFail(error,@"Unassigned runtime component."); return nil;
      }
    }
  }
  return meta;
}
static BOOL SetupVerify(NSString *root, NSDictionary *files, NSError **error) {
  NSFileManager *fm=NSFileManager.defaultManager;
  NSString *base=root.stringByResolvingSymlinksInPath;
  for(NSString *relative in files){
    NSString *path=[root stringByAppendingPathComponent:relative];
    if(!SetupRelative(relative)||![path.stringByResolvingSymlinksInPath hasPrefix:[base stringByAppendingString:@"/"]]||
       [fm destinationOfSymbolicLinkAtPath:path error:nil]||![SetupHash(path) isEqual:files[relative]])
      return SetupFail(error,[NSString stringWithFormat:@"Missing or incompatible component: %@ / 文件缺失或版本不匹配。",relative]);
  }return YES;
}
// Apply the same integrity check to extracted, cached and imported runtimes.
static BOOL SetupVerifyRuntime(NSString *root, NSDictionary *meta, NSError **error) {
  if (!SetupVerify(root, meta[@"runtime_files"], error)) return NO;
  NSString *base = [root.stringByResolvingSymlinksInPath stringByAppendingString:@"/"];
  for (NSString *relative in meta[@"runtime_links"]) {
    NSString *path = [root stringByAppendingPathComponent:relative];
    NSString *link = [NSFileManager.defaultManager destinationOfSymbolicLinkAtPath:path error:nil];
    NSString *target = [[path.stringByDeletingLastPathComponent stringByAppendingPathComponent:link ?: @""] stringByStandardizingPath];
    if (!link || link.isAbsolutePath || ![link isEqual:meta[@"runtime_links"][relative]] ||
        ![target.stringByResolvingSymlinksInPath hasPrefix:base] ||
        ![path.stringByResolvingSymlinksInPath hasPrefix:base])
      return SetupFail(error, [NSString stringWithFormat:@"Runtime link validation failed: %@", relative]);
  }
  return YES;
}
static int SetupLock(NSString *root, NSError **error) {
  if(![NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:error])return -1;
  int fd=open([[root stringByAppendingPathComponent:@"install.lock"] fileSystemRepresentation],O_CREAT|O_RDWR|O_NOFOLLOW,0600);
  if(fd<0||flock(fd,LOCK_EX|LOCK_NB)){if(fd>=0)close(fd);SetupFail(error,@"Another setup is running. Please retry when it finishes. / 另一个安装正在进行，请稍后重试。");return -1;}return fd;
}
static BOOL SetupRun(NSString *exe, NSArray *args, NSDictionary *env, NSString *cwd, NSString *log, double timeout, NSError **error, BOOL allowAbsent=NO) {
  NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:exe];task.arguments=args;task.environment=env;
  task.currentDirectoryURL=[NSURL fileURLWithPath:cwd];
  [NSFileManager.defaultManager createFileAtPath:log contents:nil attributes:nil];
  NSFileHandle *out=[NSFileHandle fileHandleForWritingAtPath:log];task.standardOutput=out?:NSFileHandle.fileHandleWithNullDevice;task.standardError=task.standardOutput;
  BOOL launched=[task launchAndReturnError:error];[out closeFile];if(!launched)return NO;
  if(!LWWaitForWineTask(task,timeout))return SetupFail(error,[NSString stringWithFormat:@"Setup timed out. Retry; log: %@",log]);
  return task.terminationStatus==0||(allowAbsent&&task.terminationStatus==1)||SetupFail(error,[NSString stringWithFormat:@"Setup command failed (%d). Log: %@",task.terminationStatus,log]);
}
// Runs only on the setup worker. Download callbacks use a private URLSession queue.
static NSString *SetupDownload(NSDictionary *item, NSString *root, void (^progress)(NSString *,double), NSError **error) {
  NSFileManager *fm=NSFileManager.defaultManager;
  NSString *cache=[root stringByAppendingPathComponent:@"downloads"];
  if (![fm createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:nil error:error]) return nil;
  NSString *dest=[cache stringByAppendingPathComponent:[item[@"sha256"] stringByAppendingString:@".tar.xz"]];
  if ([[fm attributesOfItemAtPath:dest error:nil][NSFileSize] unsignedLongLongValue]==[item[@"bytes"] unsignedLongLongValue] &&
      [SetupHash(dest) isEqual:item[@"sha256"]]) return dest;
  [fm removeItemAtPath:dest error:nil];
  NSString *partial=[cache stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
  config.timeoutIntervalForRequest=60; config.timeoutIntervalForResource=900;
  NSURLSession *session=[NSURLSession sessionWithConfiguration:config];
  dispatch_semaphore_t done=dispatch_semaphore_create(0);
  __block NSError *failure=nil;
  NSURLSessionDownloadTask *task=[session downloadTaskWithURL:[NSURL URLWithString:item[@"url"]]
    completionHandler:^(NSURL *location, NSURLResponse *response, NSError *downloadError) {
      failure=downloadError;
      if (!failure && (![response.URL.scheme isEqual:@"https"] || ![response isKindOfClass:NSHTTPURLResponse.class] ||
                       ((NSHTTPURLResponse *)response).statusCode!=200)) SetupFail(&failure,@"Download server returned an invalid response.");
      if (!failure) [fm moveItemAtURL:location toURL:[NSURL fileURLWithPath:partial] error:&failure];
      dispatch_semaphore_signal(done);
    }];
  [task resume];
  while (dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))!=0) {
    progress([NSString stringWithFormat:@"Downloading %@ / 正在下载 %.1f / %.1f MB",item[@"id"],
              task.countOfBytesReceived/1000000.0,[item[@"bytes"] doubleValue]/1000000.0],.07);
  }
  [session finishTasksAndInvalidate];
  if (!failure && ([[fm attributesOfItemAtPath:partial error:nil][NSFileSize] unsignedLongLongValue]!=[item[@"bytes"] unsignedLongLongValue] ||
                   ![SetupHash(partial) isEqual:item[@"sha256"]])) SetupFail(&failure,@"Downloaded component failed integrity verification. Please retry. / 下载校验失败，请重试。");
  if (!failure) [fm moveItemAtPath:partial toPath:dest error:&failure];
  if (failure) { [fm removeItemAtPath:partial error:nil]; if(error)*error=failure; return nil; }
  return dest;
}
static BOOL SetupAssemble(NSString *stage, NSString *root, NSDictionary *meta, void (^progress)(NSString *,double), NSError **error) {
  NSFileManager *fm=NSFileManager.defaultManager;
  NSString *sources=[root stringByAppendingPathComponent:[@".sources-" stringByAppendingString:NSUUID.UUID.UUIDString]];
  if (![fm createDirectoryAtPath:sources withIntermediateDirectories:NO attributes:nil error:error]) return NO;
  BOOL ok=YES;
  for (NSDictionary *item in meta[@"downloads"]) {
    NSString *archive=SetupDownload(item,root,progress,error);
    if (!archive) {ok=NO;break;}
    NSString *source=[sources stringByAppendingPathComponent:item[@"id"]];
    progress([NSString stringWithFormat:@"Extracting %@ / 正在解压组件",item[@"id"]],.09);
    if (![fm createDirectoryAtPath:source withIntermediateDirectories:NO attributes:nil error:error] ||
        !SetupRun(@"/usr/bin/tar",@[@"-xf",archive,@"-C",source],@{@"COPYFILE_DISABLE":@"1",@"PATH":@"/usr/bin:/bin"},root,[root stringByAppendingPathComponent:@"extract-source.log"],300,error)) {ok=NO;break;}
    progress(@"Installing verified components / 安装已校验组件",.10);
    for (NSString *relative in meta[@"source_files"]) {
      NSDictionary *entry=meta[@"source_files"][relative];
      if (![entry[@"archive"] isEqual:item[@"id"]]) continue;
      NSString *path=[source stringByAppendingPathComponent:entry[@"path"]];
      NSString *resolved=path.stringByResolvingSymlinksInPath;
      NSString *target=[stage stringByAppendingPathComponent:relative];
      if (![resolved hasPrefix:[source.stringByResolvingSymlinksInPath stringByAppendingString:@"/"]] ||
          [fm destinationOfSymbolicLinkAtPath:path error:nil] ||
          ![[fm attributesOfItemAtPath:path error:nil][NSFileType] isEqual:NSFileTypeRegular]) {
        ok=SetupFail(error,@"Invalid source archive component."); break;
      }
      if (![fm createDirectoryAtPath:target.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error] ||
          ![fm copyItemAtPath:path toPath:target error:error]) {ok=NO;break;}
    }
    // Keep peak disk usage bounded: only one vendor archive is expanded at once.
    [fm removeItemAtPath:source error:nil];
    if (!ok) break;
  }
  [fm removeItemAtPath:sources error:nil];
  return ok;
}
static BOOL SetupCreateLinks(NSString *stage, NSDictionary *links, NSError **error) {
  NSFileManager *fm=NSFileManager.defaultManager;
  NSString *base=[stage.stringByResolvingSymlinksInPath stringByAppendingString:@"/"];
  for (NSString *relative in links) {
    NSString *link=links[relative], *path=[stage stringByAppendingPathComponent:relative];
    if (![link isKindOfClass:NSString.class] || !link.length || link.isAbsolutePath ||
        ![[[path.stringByDeletingLastPathComponent stringByAppendingPathComponent:link] stringByStandardizingPath].stringByResolvingSymlinksInPath hasPrefix:base])
      return SetupFail(error,@"Invalid runtime link.");
    if (![fm createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error] ||
        ![fm createSymbolicLinkAtPath:path withDestinationPath:link error:error]) return NO;
  }
  return YES;
}
static NSString *SetupComponents(NSString *resources, NSString *root, NSDictionary *meta, void (^progress)(NSString *,double), NSError **error) {
  NSString *dest=[root stringByAppendingPathComponent:meta[@"archive_sha256"]];
  if([NSFileManager.defaultManager fileExistsAtPath:dest]){
    progress(@"Checking installed components / 检查已安装组件",.12);
    if(SetupVerifyRuntime(dest,meta,error))return dest;
    return nil;
  }
  progress(@"Verifying runtime package / 校验运行时安装包",.03);
  BOOL online=[meta[@"schema"] integerValue]==2;
  NSString *archive=[resources stringByAppendingPathComponent:online?@"RuntimeOverlay.tar.gz":@"FreeRuntime.tar.gz"];
  if(![SetupHash(archive) isEqual:meta[@"archive_sha256"]]){SetupFail(error,@"The runtime package is missing or damaged. Download the full setup app again. / 运行时安装包缺失或损坏。");return nil;}
  NSDictionary *disk=[NSFileManager.defaultManager attributesOfFileSystemForPath:root error:error];
  if([disk[NSFileSystemFreeSize] unsignedLongLongValue]<[meta[@"requires_free_bytes"] unsignedLongLongValue]){SetupFail(error,@"At least 6 GB of free space is required. / 至少需要 6 GB 可用空间。");return nil;}
  NSString *stage=[root stringByAppendingPathComponent:[@".components-" stringByAppendingString:NSUUID.UUID.UUIDString]];
  if(![NSFileManager.defaultManager createDirectoryAtPath:stage withIntermediateDirectories:NO attributes:nil error:error])return nil;
  progress(@"Installing Wine, DXMT and media components / 安装播放组件",.10);
  // The archive is app-owned and authenticated against the pinned SHA before tar runs.
  BOOL ok=!online||SetupAssemble(stage,root,meta,progress,error);
  if(ok)ok=SetupRun(@"/usr/bin/tar",@[@"-xzf",archive,@"-C",stage],@{@"COPYFILE_DISABLE":@"1",@"PATH":@"/usr/bin:/bin"},root,[root stringByAppendingPathComponent:@"extract.log"],300,error);
  if(ok&&online)ok=SetupCreateLinks(stage,meta[@"runtime_links"],error);
  if(ok)ok=SetupVerifyRuntime(stage,meta,error);
  if(ok)ok=[NSFileManager.defaultManager moveItemAtPath:stage toPath:dest error:error];
  if(!ok){[NSFileManager.defaultManager removeItemAtPath:stage error:nil];return nil;}return dest;
}
BOOL LWSetupRuntimeReady(void) {
  NSString *runtime=NSProcessInfo.processInfo.environment[@"LIVEWALLPAPER_WINE_RUNTIME"]?:[NSUserDefaults.standardUserDefaults stringForKey:@"WineRuntimePath"];
  if(!runtime.length)return NO;
  for(NSString *path in @[@"runtime.json",@"WinePlayer.app/Contents/MacOS/wine",@"wine/bin/wineserver",@"desktop_window_bridge.dylib",@"window-playback-control.exe",@"engine/assets/fonts/RobotoMono-Regular.ttf"])
    if(![NSFileManager.defaultManager fileExistsAtPath:[runtime stringByAppendingPathComponent:path]])return NO;
  return [SetupHash([runtime stringByAppendingPathComponent:@"engine/wallpaper64.exe"]) isEqual:@"40e2ce021e9352324fadb3b8f72b8ba2a7ee95b71cc571d5b9f84be75cd993b0"];
}
static void SetupProgress(void (^callback)(NSString *,double), NSString *text,double value){dispatch_async(dispatch_get_main_queue(),^{callback(text,value);});}
void LWSetupPrepareComponents(void (^progress)(NSString *,double), void (^completion)(NSString *)) {
  NSString *resources=NSBundle.mainBundle.resourcePath,*root=SetupRoot();
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
    NSError *error=nil;int lock=SetupLock(root,&error);NSDictionary *meta=lock>=0?SetupManifest(resources,&error):nil;
    if(meta)SetupComponents(resources,root,meta,^(NSString *text,double value){SetupProgress(progress,text,value);},&error);
    if(lock>=0){flock(lock,LOCK_UN);close(lock);}NSString *failure=error.localizedDescription;
    dispatch_async(dispatch_get_main_queue(),^{completion(failure);});
  }});
}
static NSMutableDictionary *SetupWineEnvironment(NSString *runtime, NSString *prefix, NSString *resources) {
  NSMutableDictionary *env=[NSProcessInfo.processInfo.environment mutableCopy];LWConfigureWineRuntimeEnvironment(env,runtime);
  env[@"WINEPREFIX"]=prefix;env[@"WINEDEBUG"]=@"-all,err+all";
  env[@"WINEDLLOVERRIDES"]=@"d3d11,dxgi,d3d10core,winemetal=b;mscoree,mshtml=;winemenubuilder.exe=d";
  NSString *gst=[runtime stringByAppendingPathComponent:@"Frameworks/GStreamer.framework/Versions/1.0"];
  env[@"DYLD_FALLBACK_LIBRARY_PATH"]=[NSString stringWithFormat:@"%@:%@",[gst stringByAppendingPathComponent:@"lib"],[runtime stringByAppendingPathComponent:@"lib"]];
  env[@"GST_PLUGIN_SYSTEM_PATH_1_0"]=[gst stringByAppendingPathComponent:@"lib/gstreamer-1.0"];
  env[@"GST_PLUGIN_PATH_1_0"]=@"";env[@"GST_PLUGIN_SCANNER"]=[gst stringByAppendingPathComponent:@"libexec/gstreamer-1.0/gst-plugin-scanner"];
  env[@"GST_REGISTRY"]=[prefix stringByAppendingPathComponent:@"gstreamer-registry.x86_64.bin"];
  env[@"DYLD_INSERT_LIBRARIES"]=[resources stringByAppendingPathComponent:@"playback/bin/wine_volume.dylib"];
  env[@"LW_WINE_DESKTOP_ENABLE"]=@"1";env[@"LW_WINE_TARGET_TITLE"]=@"LiveWallpaper-Wine-Setup";env[@"LW_WINE_SETUP"]=@"1";
  return env;
}
static NSString *SetupImport(NSString *source,NSString *resources,NSString *root,NSDictionary *meta,NSArray *screens,void (^progress)(NSString *,double),NSError **error) {
  NSFileManager *fm=NSFileManager.defaultManager;
  BOOL isDirectory=NO;if(![fm fileExistsAtPath:source isDirectory:&isDirectory]){SetupFail(error,@"Wallpaper Engine folder was not found.");return nil;}
  if(!isDirectory)source=source.stringByDeletingLastPathComponent;
  source=source.stringByResolvingSymlinksInPath;
  if(![SetupHash([source stringByAppendingPathComponent:@"wallpaper64.exe"]) isEqual:meta[@"engine_sha256"]]){
    SetupFail(error,@"This release supports the original Wallpaper Engine 2.8.42 files. Select its installation folder or wallpaper64.exe. / 请选择原版 2.8.42 安装目录或 wallpaper64.exe，其他版本尚未验证。");return nil;
  }
  progress(@"Checking Wallpaper Engine components / 校验引擎完整性",.32);
  if(!SetupVerify(source,meta[@"engine_files"],error))return nil;
  NSString *components=SetupComponents(resources,root,meta,progress,error);if(!components)return nil;
  NSString *runtime=[root stringByAppendingPathComponent:[@"R-" stringByAppendingString:[meta[@"archive_sha256"] substringToIndex:16]]];
  if(![fm fileExistsAtPath:runtime]){
    NSString *stage=[root stringByAppendingPathComponent:[@".import-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    progress(@"Importing engine files / 导入引擎文件",.42);
    BOOL ok=SetupRun(@"/bin/cp",@[@"-cR",components,stage],NSProcessInfo.processInfo.environment,root,[root stringByAppendingPathComponent:@"copy.log"],180,error);
    NSString *engine=[stage stringByAppendingPathComponent:@"engine"];
    if(ok)ok=[fm createDirectoryAtPath:engine withIntermediateDirectories:YES attributes:nil error:error];
    NSUInteger count=0,total=[meta[@"engine_files"] count];
    if(ok)for(NSString *relative in meta[@"engine_files"]){
      NSString *target=[engine stringByAppendingPathComponent:relative];
      if(![fm createDirectoryAtPath:target.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]||
         ![fm copyItemAtPath:[source stringByAppendingPathComponent:relative] toPath:target error:error]){ok=NO;break;}
      if(++count%100==0)progress(@"Importing engine files / 导入引擎文件",.42+.18*count/total);
    }
    if(ok)ok=SetupVerify(engine,meta[@"engine_files"],error);
    if(ok)ok=[fm moveItemAtPath:stage toPath:runtime error:error];
    if(!ok){[fm removeItemAtPath:stage error:nil];return nil;}
  }else if(!SetupVerify([runtime stringByAppendingPathComponent:@"engine"],meta[@"engine_files"],error)||!SetupVerifyRuntime(runtime,meta,error))return nil;
  NSString *configPath=[runtime stringByAppendingPathComponent:@"engine/config.json"];
  if(![fm fileExistsAtPath:configPath]) {
    NSDictionary *config=@{NSUserName():@{@"general":@{@"user":@{@"videoframework":@"mf",@"videohardwareacceleration":@NO}}}};
    NSData *data=[NSJSONSerialization dataWithJSONObject:config options:NSJSONWritingPrettyPrinted error:error];
    if(!data||![data writeToFile:configPath options:NSDataWritingAtomic error:error])return nil;
  }
  NSString *sessions=[runtime stringByAppendingPathComponent:@"sessions"];
  NSUInteger index=0;
  for(NSDictionary *screen in screens){
    NSString *uuid=screen[@"uuid"];
    if(![[NSUUID alloc] initWithUUIDString:uuid]){SetupFail(error,@"Invalid display identifier.");return nil;}
    NSString *directory=[sessions stringByAppendingPathComponent:uuid],*prefix=[directory stringByAppendingPathComponent:@"prefix"];
    progress(@"Configuring private playback environment and fonts / 配置独立环境与字体",.65+.25*index/MAX((NSUInteger)1,screens.count));
    if(!LWPrepareWineCompatibility(runtime,prefix,error))return nil;
    NSMutableDictionary *env=SetupWineEnvironment(runtime,prefix,resources);
    NSString *server=[runtime stringByAppendingPathComponent:@"wine/bin/wineserver"];
    BOOL ok=SetupRun([runtime stringByAppendingPathComponent:@"WinePlayer.app/Contents/MacOS/wine"],@[@"wineboot.exe",@"--init"],env,runtime,[directory stringByAppendingPathComponent:@"setup.log"],180,error);
    if(ok)ok=SetupRun([runtime stringByAppendingPathComponent:@"WinePlayer.app/Contents/MacOS/wine"],
      @[@"reg.exe",@"add",@"HKCU\\Software\\Wine\\Drivers",@"/v",@"Audio",@"/t",@"REG_SZ",@"/d",@"coreaudio",@"/f"],
      env,runtime,[directory stringByAppendingPathComponent:@"setup-audio.log"],30,error);
    // Stop only this setup prefix, on both success and failure; never leave a
    // bootstrap server racing the next retry or the registry configuration.
    NSError *stopError=nil;
    BOOL stopped=SetupRun(server,@[@"-k"],env,runtime,[directory stringByAppendingPathComponent:@"setup-stop.log"],10,&stopError,YES);
    BOOL flushed=SetupRun(server,@[@"-w"],env,runtime,[directory stringByAppendingPathComponent:@"setup-wait.log"],15,&stopError);
    if(!ok)return nil;
    if(!stopped||!flushed){if(error)*error=stopError;return nil;}
    if(![fm fileExistsAtPath:[prefix stringByAppendingPathComponent:@"system.reg"]]){SetupFail(error,@"Wine environment initialization did not finish. Please retry.");return nil;}
    if(!LWSyncWineMediaModules(runtime,prefix,error)||!LWSetWineRetina(prefix,[screen[@"retina"] boolValue],error))return nil;
    index++;
  }
  if(!screens.count){SetupFail(error,@"No display was found. Connect a display and retry.");return nil;}
  NSData *receipt=[NSJSONSerialization dataWithJSONObject:@{@"schema":@1,@"runtime_sha256":meta[@"archive_sha256"],@"engine_sha256":meta[@"engine_sha256"],@"screens":screens} options:NSJSONWritingPrettyPrinted error:error];
  if(!receipt||![receipt writeToFile:[runtime stringByAppendingPathComponent:@"setup-complete.json"] options:NSDataWritingAtomic error:error])return nil;
  progress(@"Ready / 配置完成",1);return runtime;
}
void LWSetupImportEngine(NSString *source,NSArray<NSDictionary *> *screens,void (^progress)(NSString *,double),void (^completion)(NSString *,NSString *)) {
  NSString *resources=NSBundle.mainBundle.resourcePath,*root=SetupRoot();
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
    NSError *error=nil;int lock=SetupLock(root,&error);NSDictionary *meta=lock>=0?SetupManifest(resources,&error):nil;
    NSString *runtime=meta?SetupImport(source,resources,root,meta,screens,^(NSString *text,double value){SetupProgress(progress,text,value);},&error):nil;
    if(lock>=0){flock(lock,LOCK_UN);close(lock);}NSString *failure=error.localizedDescription;
    dispatch_async(dispatch_get_main_queue(),^{
      if(runtime){
        [NSUserDefaults.standardUserDefaults setObject:runtime forKey:@"WineRuntimePath"];
        [NSUserDefaults.standardUserDefaults setObject:[runtime stringByAppendingPathComponent:@"sessions"] forKey:@"WineStatePath"];
        if(![NSUserDefaults.standardUserDefaults objectForKey:@"wallpapervolume"]){[NSUserDefaults.standardUserDefaults setDouble:0 forKey:@"wallpapervolume"];[NSUserDefaults.standardUserDefaults setDouble:0 forKey:@"wallpapervolumeprecentage"];}
        [NSUserDefaults.standardUserDefaults synchronize];
        setenv("LIVEWALLPAPER_WINE_RUNTIME",runtime.fileSystemRepresentation,1);
      }
      completion(runtime,failure?:(!runtime?@"Setup failed. Please retry.":nil));
    });
  }});
}
