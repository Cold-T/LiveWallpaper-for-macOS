#pragma once
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import "WineCompatibility.h"
#import "WinePrefix.h"
#import "WineMediaModules.h"
#import "DesktopSession.h"
#import "WineRuntimeEnvironment.h"
#import "WineTaskWait.h"
#include <limits.h>

// Startup retries share the one 90s launch deadline; post-start failures retain
// the existing three-consecutive-failure policy.
static BOOL LWControlStartupGrace(NSDictionary *session) {
  NSDate *started = session[@"started"];
  return ![session[@"playbackStarted"] boolValue] && [started isKindOfClass:NSDate.class] &&
         -started.timeIntervalSinceNow <= 90;
}
static BOOL LWRecordControlFailure(NSMutableDictionary *session) {
  NSString *key = LWControlStartupGrace(session) ? @"startupControlFailures" : @"controlFailures";
  session[key] = @([session[key] unsignedIntegerValue] + 1);
  return [key isEqual:@"controlFailures"] && [session[key] unsignedIntegerValue] == 3;
}
static void LWAbsorbRendererStatus(NSMutableDictionary *session, NSDictionary *status, BOOL alive) {
  if ([status[@"rendererReady"] boolValue] && alive) session[@"ready"] = @YES;
  if ([status[@"firstFramePresented"] boolValue] && alive) session[@"playbackStarted"] = @YES;
}
static void LWAppendControlLog(NSString *path, NSString *text) {
  NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
  int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW | O_CLOEXEC, 0600);
  if (fd < 0) return;
  const char *bytes = (const char *)data.bytes; size_t remaining = data.length;
  while (remaining) {
    ssize_t count = write(fd, bytes, remaining);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) break;
    bytes += count; remaining -= count;
  }
  close(fd);
}
static NSTimer *LWPlaybackMonitorTimer(void (^block)(NSTimer *)) {
  NSTimer *timer = [NSTimer timerWithTimeInterval:2 repeats:YES block:block];
  [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
  return timer;
}

static NSString *LWPlaybackVolumeValue(void) {
  return [NSString stringWithFormat:@"%.6f", fmax(0, fmin(1, [NSUserDefaults.standardUserDefaults doubleForKey:@"wallpapervolume"]))];
}

// Native supervisor. Wine, original Windows files, prefix and logs live in an
// explicitly prepared runtime directory. No Python is needed for playback.
@interface LWWinePlayback : NSObject
@property NSMutableDictionary<NSString *, NSDictionary *> *sessions;
@property NSTimer *monitor;
@property BOOL locked;
@property BOOL sleeping;
@property(copy) void (^stateChanged)(void);
- (BOOL)start:(NSString *)project screen:(NSScreen *)screen error:(NSError **)error;
- (BOOL)stopDisplay:(NSString *)uuid;
- (void)stopAll;
- (void)updateVolume;
@end

@implementation LWWinePlayback
- (instancetype)init {
  if ((self = [super init])) {
    _sessions = [NSMutableDictionary dictionary];
    NSNotificationCenter *workspace = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspace addObserver:self selector:@selector(sleep:) name:NSWorkspaceWillSleepNotification object:nil];
    [workspace addObserver:self selector:@selector(wake:) name:NSWorkspaceDidWakeNotification object:nil];
    [NSDistributedNotificationCenter.defaultCenter addObserver:self selector:@selector(lock:) name:@"com.apple.screenIsLocked" object:nil];
    [NSDistributedNotificationCenter.defaultCenter addObserver:self selector:@selector(unlock:) name:@"com.apple.screenIsUnlocked" object:nil];
    _locked = LWDesktopSessionIsLocked();
    __weak LWWinePlayback *weakSelf = self;
    _monitor = LWPlaybackMonitorTimer(^(NSTimer *timer) { [weakSelf tick]; });
  }
  return self;
}
- (void)dealloc {
  [_monitor invalidate];
  [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
  [NSDistributedNotificationCenter.defaultCenter removeObserver:self];
}
- (void)updateVolume {
  NSString *value = LWPlaybackVolumeValue();
  for (NSDictionary *session in self.sessions.allValues) {
    NSError *error = nil;
    if (![value writeToFile:[session[@"directory"] stringByAppendingPathComponent:@"volume.txt"] atomically:YES encoding:NSUTF8StringEncoding error:&error])
      [NSNotificationCenter.defaultCenter postNotificationName:@"LWWinePlaybackError" object:error.localizedDescription];
  }
}
- (void)sleep:(NSNotification *)note { self.sleeping = YES; [self tick]; }
- (void)wake:(NSNotification *)note { self.sleeping = NO; [self tick]; }
- (void)lock:(NSNotification *)note { self.locked = YES; [self tick]; }
- (void)unlock:(NSNotification *)note { self.locked = NO; [self tick]; }
- (NSString *)runtime {
  NSString *override = NSProcessInfo.processInfo.environment[@"LIVEWALLPAPER_WINE_RUNTIME"];
  NSString *selected = override.length ? override : [NSUserDefaults.standardUserDefaults stringForKey:@"WineRuntimePath"];
  // Foundation rewrites /private/tmp to /tmp on macOS. Wine builtin lookup
  // and PE image identity need the filesystem canonical path instead.
  char resolved[PATH_MAX];
  if (selected.length && realpath(selected.fileSystemRepresentation, resolved))
    return [NSString stringWithUTF8String:resolved];
  return selected;
}
- (NSString *)stateRoot {
  NSString *override = NSProcessInfo.processInfo.environment[@"LIVEWALLPAPER_WINE_STATE"];
  if (override.length) return override;
  NSString *managed = [NSUserDefaults.standardUserDefaults stringForKey:@"WineStatePath"];
  if (managed.length) return managed;
  NSString *support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
  return [support stringByAppendingPathComponent:@"LiveWallpaper-Wine"];
}
- (NSMutableDictionary *)environment:(NSString *)runtime prefix:(NSString *)prefix {
  NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
  env[@"WINEPREFIX"] = prefix;
  NSString *gst = [runtime stringByAppendingPathComponent:@"Frameworks/GStreamer.framework/Versions/1.0"];
  env[@"DYLD_FALLBACK_LIBRARY_PATH"] = [NSString stringWithFormat:@"%@:%@", [gst stringByAppendingPathComponent:@"lib"], [runtime stringByAppendingPathComponent:@"lib"]];
  env[@"GST_PLUGIN_SYSTEM_PATH_1_0"] = [gst stringByAppendingPathComponent:@"lib/gstreamer-1.0"];
  env[@"GST_PLUGIN_PATH_1_0"] = @"";
  env[@"GST_PLUGIN_SCANNER"] = [gst stringByAppendingPathComponent:@"libexec/gstreamer-1.0/gst-plugin-scanner"];
  env[@"GST_REGISTRY"] = [prefix stringByAppendingPathComponent:@"gstreamer-registry.x86_64.bin"];
  // Official Sikarugir Template 1.0.21 sets this in wineEnvironmentVariables().
  // Its Wine 11 ntdll exits before initialization when the marker is absent.
  LWConfigureWineRuntimeEnvironment(env, runtime);
  NSString *icd = [runtime stringByAppendingPathComponent:@"vulkan/icd.d/MoltenVK_icd.json"];
  if ([NSFileManager.defaultManager fileExistsAtPath:icd]) {
    env[@"CX_LIBVULKAN"] = [runtime stringByAppendingPathComponent:@"lib/libvulkan.1.dylib"];
    env[@"VK_DRIVER_FILES"] = icd;
    env[@"VK_ICD_FILENAMES"] = icd;
  }
  env[@"WINEDEBUG"] = @"-all,err+all";
  env[@"WINEDLLOVERRIDES"] = @"d3d11,dxgi,d3d10core,winemetal=b;mscoree,mshtml=";
  [env removeObjectForKey:@"DYLD_INSERT_LIBRARIES"];
  return env;
}
- (NSTask *)run:(NSString *)executable args:(NSArray *)args environment:(NSDictionary *)env cwd:(NSString *)cwd log:(NSString *)log error:(NSError **)error {
  NSTask *task = [NSTask new];
  task.executableURL = [NSURL fileURLWithPath:executable];
  task.arguments = args; task.environment = env;
  task.currentDirectoryURL = [NSURL fileURLWithPath:cwd];
  [NSFileManager.defaultManager createFileAtPath:log contents:nil attributes:nil];
  NSFileHandle *output = [NSFileHandle fileHandleForWritingAtPath:log];
  task.standardOutput = output ?: NSFileHandle.fileHandleWithNullDevice;
  task.standardError = task.standardOutput;
  if (![task launchAndReturnError:error]) { [output closeFile]; return nil; }
  [output closeFile];
  return task;
}
- (BOOL)stopPrefix:(NSString *)prefix runtime:(NSString *)runtime directory:(NSString *)directory error:(NSError **)error {
  NSString *server = [runtime stringByAppendingPathComponent:@"wine/bin/wineserver"];
  NSDictionary *env = [self environment:runtime prefix:prefix];
  NSTask *kill = [self run:server args:@[@"-k"] environment:env cwd:runtime log:[directory stringByAppendingPathComponent:@"stop.log"] error:error];
  if (!kill) return NO;
  if (!LWWaitForWineTask(kill, 3)) {
    if (error) *error = [NSError errorWithDomain:@"LiveWallpaperWine" code:7 userInfo:@{NSLocalizedDescriptionKey:@"Stopping the private player timed out. Please try Stop again."}];
    return NO;
  }
  // Wine returns 1 when no lock owner/server exists. -k exits immediately,
  // so a combined '-k -w' never reaches the wait option (server/main.c).
  if (kill.terminationStatus != 0 && kill.terminationStatus != 1) {
    if (error) *error = [NSError errorWithDomain:@"LiveWallpaperWine" code:3 userInfo:@{NSLocalizedDescriptionKey:@"Unable to stop the private Wine server; see stop.log."}];
    return NO;
  }
  NSTask *wait = [self run:server args:@[@"-w"] environment:env cwd:runtime log:[directory stringByAppendingPathComponent:@"stop-wait.log"] error:error];
  if (!wait) return NO;
  if (!LWWaitForWineTask(wait, 3)) {
    if (error) *error = [NSError errorWithDomain:@"LiveWallpaperWine" code:8 userInfo:@{NSLocalizedDescriptionKey:@"Waiting for playback cleanup timed out. Please try Stop again."}];
    return NO;
  }
  if (wait.terminationStatus != 0 && error)
    *error = [NSError errorWithDomain:@"LiveWallpaperWine" code:4 userInfo:@{NSLocalizedDescriptionKey:@"Unable to wait for private Wine registry flush; see stop-wait.log."}];
  return wait.terminationStatus == 0;
}
- (BOOL)start:(NSString *)project screen:(NSScreen *)screen error:(NSError **)error {
  NSString *runtime = self.runtime;
  NSFileManager *fm = NSFileManager.defaultManager;
  for (NSString *file in @[@"WinePlayer.app/Contents/MacOS/wine", @"WinePlayer.app/Contents/MacOS/ntdll.so",
                          @"wine/bin/wineserver", @"wine/lib/wine/x86_64-windows/winegstreamer.dll",
                          @"wine/lib/wine/x86_64-unix/winegstreamer.so", @"wine/lib/wine/x86_64-windows/mfmediaengine.dll",
                          @"desktop_window_bridge.dylib", @"window-playback-control.exe", @"engine/wallpaper64.exe", @"runtime.json"]) {
    if (!runtime.length || ![fm fileExistsAtPath:[runtime stringByAppendingPathComponent:file]]) {
      if (error) *error = [NSError errorWithDomain:@"LiveWallpaperWine" code:1 userInfo:@{NSLocalizedDescriptionKey: @"请在设置中选择已准备好的 Wallpaper Engine 播放运行时目录。 / Select a prepared playback runtime in Settings."}];
      return NO;
    }
  }
  CGDirectDisplayID display = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
  CFUUIDRef displayUUID = CGDisplayCreateUUIDFromDisplayID(display);
  if (!displayUUID) return NO;
  NSString *uuid = CFBridgingRelease(CFUUIDCreateString(NULL, displayUUID)); CFRelease(displayUUID);
  NSDictionary *existing = self.sessions[uuid];
  NSString *projectKey = project.stringByResolvingSymlinksInPath.stringByStandardizingPath;
  // Re-selecting an already launching/playing wallpaper is idempotent. In
  // particular, do not kill a Wine server that is still acquiring its lock.
  if ([existing[@"project"] isEqual:projectKey] && [existing[@"runtime"] isEqual:runtime] &&
      ![existing[@"stopping"] boolValue] && ![existing[@"stopFailed"] boolValue] &&
      [(NSTask *)existing[@"task"] isRunning]) return YES;
  BOOL hadSession = existing != nil;
  if (![self stopDisplay:uuid]) {
    if (error) *error = [NSError errorWithDomain:@"LiveWallpaperWine" code:6 userInfo:@{NSLocalizedDescriptionKey:@"The previous private player could not be stopped. Check stop.log before retrying."}];
    return NO;
  }
  NSString *directory = [self.stateRoot stringByAppendingPathComponent:uuid];
  if (![fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) return NO;
  NSString *prefix = [directory stringByAppendingPathComponent:@"prefix"];
  if (!hadSession && [fm fileExistsAtPath:prefix]) {
    if (![self stopPrefix:prefix runtime:runtime directory:directory error:error]) return NO;
  }
  if (!LWPrepareWineCompatibility(runtime, prefix, error)) return NO;
  // Fonts create windows/Fonts, never system32. Sync only existing stopped
  // prefixes; a fresh prefix still gets its media modules from Wine bootstrap.
  if (!LWSyncWineMediaModules(runtime, prefix, error)) return NO;
  BOOL retina = screen.backingScaleFactor >= 1.5;
  if (!LWSetWineRetina(prefix, retina, error)) return NO;
  NSString *status = [directory stringByAppendingPathComponent:@"window.json"];
  [fm removeItemAtPath:status error:nil];
  NSString *title = [@"LiveWallpaper-Wine-" stringByAppendingString:uuid];
  NSMutableDictionary *env = [self environment:runtime prefix:prefix];
  NSString *volumeLibrary = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"playback/bin/wine_volume.dylib"];
  if (![fm fileExistsAtPath:volumeLibrary]) {
    if (error) *error = [NSError errorWithDomain:@"LiveWallpaper" code:70 userInfo:@{NSLocalizedDescriptionKey:@"Wallpaper audio module is missing. Reinstall the app."}];
    return NO;
  }
  NSString *volumeFile = [directory stringByAppendingPathComponent:@"volume.txt"];
  NSString *volumeValue = LWPlaybackVolumeValue();
  if (![volumeValue writeToFile:volumeFile atomically:YES encoding:NSUTF8StringEncoding error:error]) return NO;
  env[@"LW_WINE_VOLUME_FILE"] = volumeFile;
  env[@"DYLD_INSERT_LIBRARIES"] = [NSString stringWithFormat:@"%@:%@", volumeLibrary, [runtime stringByAppendingPathComponent:@"desktop_window_bridge.dylib"]];
  env[@"LW_WINE_TARGET_TITLE"] = title;
  env[@"LW_WINE_DESKTOP_ENABLE"] = @"1"; env[@"LW_WINE_DESKTOP_FILL"] = @"1";
  env[@"LW_WINE_DESKTOP_INPUT"] = @"1";
  env[@"LW_WINE_DISPLAY_UUID"] = uuid; env[@"LW_WINE_STATUS_FILE"] = status;
  NSString *winpath = [@"Z:" stringByAppendingString:[project.stringByResolvingSymlinksInPath stringByReplacingOccurrencesOfString:@"/" withString:@"\\"]];
  NSArray *args = @[@"wallpaper64.exe", @"-silent", @"-control", @"openWallpaper", @"-file", winpath,
    @"-playInWindow", title, @"-borderless", @"-width", [NSString stringWithFormat:@"%.0f", screen.frame.size.width * (retina ? 2 : 1)],
    @"-height", [NSString stringWithFormat:@"%.0f", screen.frame.size.height * (retina ? 2 : 1)], @"-x", @"0", @"-y", @"0"];
  NSString *engine = [runtime stringByAppendingPathComponent:@"engine"];
  NSTask *task = [self run:[runtime stringByAppendingPathComponent:@"WinePlayer.app/Contents/MacOS/wine"] args:args environment:env cwd:engine log:[directory stringByAppendingPathComponent:@"playback.log"] error:error];
  if (!task) return NO;
  self.sessions[uuid] = @{@"task":task, @"project":projectKey, @"runtime":runtime, @"prefix":prefix, @"directory":directory,
                        @"status":status, @"title":title, @"started":NSDate.date, @"paused":@NO, @"controlApplied":@NO, @"ready":@NO};
  return YES;
}
- (BOOL)stopDisplay:(NSString *)uuid {
  NSMutableDictionary *session = [self.sessions[uuid] mutableCopy];
  if (!session) return YES;
  if ([session[@"stopping"] boolValue]) return NO;
  // Quiesce monitoring first: wait loops can dispatch timers/completions. No
  // control helper may revive this prefix while its server is being stopped.
  session[@"stopping"] = @YES;
  [session removeObjectForKey:@"stopFailed"];
  self.sessions[uuid] = session;
  NSTask *renderer = session[@"task"], *control = session[@"controlTask"];
  LWCancelWineTask(control);
  LWCancelWineTask(renderer);
  BOOL controlExited = LWWaitForWineTask(control, 1);
  BOOL rendererExited = LWWaitForWineTask(renderer, 2);
  // Only this display's application-owned prefix; never killall Wine/Steam.
  NSString *runtime = session[@"runtime"];
  NSError *error = nil;
  BOOL flushed = [self stopPrefix:session[@"prefix"] runtime:runtime directory:session[@"directory"] error:&error];
  if (!flushed || !controlExited || !rendererExited) {
    session[@"stopping"] = @NO;
    session[@"stopFailed"] = @YES;
    self.sessions[uuid] = session;
    [NSNotificationCenter.defaultCenter postNotificationName:@"LWWinePlaybackError" object:error.localizedDescription ?: @"Private Wine cleanup failed; please try Stop again."];
    return NO;
  }
  [self.sessions removeObjectForKey:uuid];
  return YES;
}
- (void)stopAll { for (NSString *uuid in self.sessions.allKeys) [self stopDisplay:uuid]; }
// Global WE pause/play only visits desktop renderers. Pop-outs use the original
// scene renderer's own WM_USER+11 handler on its validated DX11 child window.
// Identification is separate and read-only; all subsequent writes pin Win32 PID.
- (void)requestWindowControl:(NSString *)uuid session:(NSMutableDictionary *)session paused:(BOOL)pause {
  NSString *runtime = session[@"runtime"];
  NSNumber *windowsPID = session[@"windowsPID"];
  BOOL identify = windowsPID == nil;
  BOOL needsPlaybackControl = ![session[@"controlApplied"] boolValue] || [session[@"paused"] boolValue] != pause;
  BOOL fit = !identify && !needsPlaybackControl && [session[@"rendererSizeMismatch"] boolValue];
  NSString *action = identify ? @"identify" : (fit ? @"fit" : (pause ? @"pause" : @"play"));
  if (fit) session[@"geometryAttempt"] = NSDate.date;
  NSString *log = [session[@"directory"] stringByAppendingPathComponent:@"control.log"];
  NSString *attemptLog = [session[@"directory"] stringByAppendingPathComponent:@"control-attempt.log"];
  LWAppendControlLog(log, [NSString stringWithFormat:@"\n[LWControl] action=%@ start\n", action]);
  NSError *error = nil;
  NSString *enginePath = [@"Z:" stringByAppendingString:[[runtime stringByAppendingPathComponent:@"engine/wallpaper64.exe"] stringByReplacingOccurrencesOfString:@"/" withString:@"\\"]];
  NSTask *control = [self run:[runtime stringByAppendingPathComponent:@"WinePlayer.app/Contents/MacOS/wine"]
      args:@[[runtime stringByAppendingPathComponent:@"window-playback-control.exe"], session[@"title"],
             windowsPID ? windowsPID.stringValue : @"0", action, enginePath]
      environment:[self environment:runtime prefix:session[@"prefix"]]
      cwd:[runtime stringByAppendingPathComponent:@"engine"] log:attemptLog error:&error];
  if (!control) {
    LWAppendControlLog(log, [NSString stringWithFormat:@"[LWControl] action=%@ launch_failed code=%ld\n", action, (long)error.code]);
    if (LWRecordControlFailure(session))
      [NSNotificationCenter.defaultCenter postNotificationName:@"LWWinePlaybackError" object:error.localizedDescription ?: @"Unable to start window playback control; see control.log."];
    return;
  }
  session[@"controlTask"] = control;
  NSTask *rendererTask = session[@"task"];
  __weak LWWinePlayback *weakSelf = self;
  void (^finished)(NSTask *) = ^(NSTask *task) {
    dispatch_async(dispatch_get_main_queue(), ^{
      LWWinePlayback *owner = weakSelf;
      NSMutableDictionary *current = [owner.sessions[uuid] mutableCopy];
      if (!current || [current[@"stopping"] boolValue] || [current[@"stopFailed"] boolValue] || current[@"task"] != rendererTask || current[@"controlTask"] != task) return;
      [current removeObjectForKey:@"controlTask"];
      BOOL success = task.terminationReason == NSTaskTerminationReasonExit && task.terminationStatus == 0;
      if (success && identify) {
        NSString *text = [NSString stringWithContentsOfFile:attemptLog encoding:NSUTF8StringEncoding error:nil];
        NSNumber *pid = nil;
        // Wine diagnostics share stderr with this log. Accept exactly one valid
        // helper result line rather than treating warnings as a JSON response.
        for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
          if (![line hasPrefix:@"{\"windowsPID\":"]) continue;
          NSDictionary *result = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
          NSNumber *candidate = [result isKindOfClass:NSDictionary.class] ? result[@"windowsPID"] : nil;
          if (pid) { pid = nil; break; }
          if ([candidate isKindOfClass:NSNumber.class]) pid = candidate;
        }
        success = [pid isKindOfClass:NSNumber.class] && pid.unsignedLongLongValue > 0 && pid.unsignedLongLongValue <= UINT32_MAX;
        if (success) current[@"windowsPID"] = pid;
      } else if (success && !fit) {
        current[@"paused"] = @(pause);
        current[@"controlApplied"] = @YES;
      }
      NSString *output = [NSString stringWithContentsOfFile:attemptLog encoding:NSUTF8StringEncoding error:nil] ?: @"";
      LWAppendControlLog(log, [NSString stringWithFormat:@"%@\n[LWControl] action=%@ reason=%ld status=%d accepted=%d startup=%d\n", output, action, (long)task.terminationReason, task.terminationStatus, success, LWControlStartupGrace(current)]);
      if (success) current[@"controlFailures"] = @0;
      else if (LWRecordControlFailure(current))
        [NSNotificationCenter.defaultCenter postNotificationName:@"LWWinePlaybackError" object:@"Unable to apply window playback control after three attempts; see control.log. Playback state has not been confirmed."];
      owner.sessions[uuid] = current;
    });
  };
  control.terminationHandler = finished;
  // NSTask may have exited before the handler was installed. The task identity
  // check above makes duplicate completion delivery harmless.
  if (!control.running) finished(control);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
    // A helper that ignores SIGTERM must not block every later control request.
    // Bound its cleanup too, and signal only this application-owned NSTask.
    (void)LWWaitForWineTask(control, 0);
  });
}
- (void)tick {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
  BOOL pause = self.locked || self.sleeping;
  if ([defaults boolForKey:@"pauseOnAppFocus"] && front && front.processIdentifier != getpid() &&
      ![front.bundleIdentifier isEqualToString:@"com.apple.finder"]) pause = YES;
  for (NSString *uuid in self.sessions.allKeys) {
    NSMutableDictionary *session = [self.sessions[uuid] mutableCopy];
    if ([session[@"stopping"] boolValue] || [session[@"stopFailed"] boolValue]) continue;
    NSData *data = [NSData dataWithContentsOfFile:session[@"status"]];
    NSDictionary *status = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSTimeInterval elapsed = -[session[@"started"] timeIntervalSinceNow];
    NSDate *modified = [NSFileManager.defaultManager attributesOfItemAtPath:session[@"status"] error:nil][NSFileModificationDate];
    BOOL alive = modified && -modified.timeIntervalSinceNow < 8;
    if (status[@"error"] && modified && -modified.timeIntervalSinceNow < 8) {
      [self stopDisplay:uuid];
      NSString *message = [NSString stringWithFormat:@"Wallpaper Engine 播放失败，已清理此显示器的播放进程。\n%@\n日志 / Log: %@", status[@"error"], [session[@"directory"] stringByAppendingPathComponent:@"playback.log"]];
      [NSNotificationCenter.defaultCenter postNotificationName:@"LWWinePlaybackError" object:message];
      if (self.stateChanged) self.stateChanged();
      continue;
    }
    LWAbsorbRendererStatus(session, status, alive);
    if ((elapsed > 90 && (![session[@"playbackStarted"] boolValue] || !alive)) || (elapsed > 10 && [session[@"ready"] boolValue] && !alive)) {
      [self stopDisplay:uuid];
      [NSNotificationCenter.defaultCenter postNotificationName:@"LWWinePlaybackError" object:@"Wallpaper Engine 未能保持播放，请查看运行日志。 / Playback stopped; check the playback log."];
      if (self.stateChanged) self.stateChanged();
      continue;
    }
    session[@"rendererSizeMismatch"] = @([status[@"rendererSizeMismatch"] boolValue]);
    NSDate *geometryAttempt = session[@"geometryAttempt"];
    BOOL fitDue = [session[@"rendererSizeMismatch"] boolValue] &&
                  (!geometryAttempt || -geometryAttempt.timeIntervalSinceNow >= 4);
    if ((fitDue || ![session[@"controlApplied"] boolValue] || [session[@"paused"] boolValue] != pause) &&
        [session[@"ready"] boolValue] && !session[@"controlTask"] &&
        (LWControlStartupGrace(session) || [session[@"controlFailures"] unsignedIntegerValue] < 3)) {
      [self requestWindowControl:uuid session:session paused:pause];
    }
    self.sessions[uuid] = session;
  }
}
@end
