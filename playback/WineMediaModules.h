#pragma once
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

static BOOL LWMediaModulesError(NSError **error, NSString *message) {
  if (error) *error = [NSError errorWithDomain:@"LiveWallpaperWineMedia" code:1
      userInfo:@{NSLocalizedDescriptionKey:message}];
  return NO;
}
static NSString *LWMediaModulesSHA(NSData *data) {
  unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, bytes);
  NSMutableString *hash = [NSMutableString string];
  for (unsigned int i = 0; i < sizeof(bytes); ++i) [hash appendFormat:@"%02x", bytes[i]];
  return hash;
}
// Hold directory descriptors and refuse symlinks at every relative component.
static int LWMediaModulesDirectory(int parent, NSString *relative) {
  int current = dup(parent);
  for (NSString *part in [relative componentsSeparatedByString:@"/"]) {
    if (current < 0) return -1;
    int next = openat(current, part.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    int saved = errno; close(current); current = next; errno = saved;
    if (current < 0) return -1;
  }
  return current;
}
static NSData *LWMediaModulesRead(int directory, NSString *name) {
  int fd = openat(directory, name.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
  if (fd < 0) return nil;
  struct stat before, after;
  NSMutableData *data = nil;
  if (!fstat(fd, &before) && S_ISREG(before.st_mode) && before.st_size >= 0 && before.st_size <= 512LL * 1024 * 1024) {
    data = [NSMutableData dataWithLength:(NSUInteger)before.st_size];
    size_t offset = 0;
    while (offset < data.length) {
      ssize_t n = read(fd, (char *)data.mutableBytes + offset, data.length - offset);
      if (n < 0 && errno == EINTR) continue;
      if (n <= 0) { data = nil; break; }
      offset += (size_t)n;
    }
    char extra;
    ssize_t n;
    do { n = read(fd, &extra, 1); } while (n < 0 && errno == EINTR);
#ifdef LW_MEDIA_MODULES_TEST_AFTER_READ
    LW_MEDIA_MODULES_TEST_AFTER_READ(fd);
#endif
    // FileProvider hydration can change timestamps without changing payload.
    // The held regular-file descriptor, full length/EOF and caller's SHA256
    // establish content identity; cloud metadata stability is not required.
    if (n != 0 || fstat(fd, &after) || !S_ISREG(after.st_mode) || before.st_size != after.st_size) data = nil;
  }
  close(fd);
  return data;
}
static BOOL LWMediaModulesPE(NSData *data) {
  const unsigned char *p = (const unsigned char *)data.bytes;
  if (data.length < 64 || p[0] != 'M' || p[1] != 'Z') return NO;
  uint32_t offset; memcpy(&offset, p + 60, 4);
  if (offset > data.length - 26) return NO;
  uint16_t machine, characteristics, magic;
  memcpy(&machine, p + offset + 4, 2); memcpy(&characteristics, p + offset + 22, 2); memcpy(&magic, p + offset + 24, 2);
  return !memcmp(p + offset, "PE\0\0", 4) && machine == 0x8664 && (characteristics & 0x2000) && magic == 0x20b;
}
// Create a complete verified temporary file in the held system32 directory.
static NSString *LWMediaModulesStage(int directory, NSData *data, mode_t mode) {
  NSString *name = [@".lw-media-" stringByAppendingString:NSUUID.UUID.UUIDString];
  int fd = openat(directory, name.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
  if (fd < 0) return nil;
  BOOL ok = YES;
  size_t offset = 0;
  while (offset < data.length) {
    ssize_t n = write(fd, (const char *)data.bytes + offset, data.length - offset);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) { ok = NO; break; }
    offset += (size_t)n;
  }
  if (ok && (fchmod(fd, mode) || fsync(fd))) ok = NO;
  if (close(fd)) ok = NO;
  if (ok) ok = [LWMediaModulesRead(directory, name) isEqualToData:data];
  if (!ok) { unlinkat(directory, name.fileSystemRepresentation, 0); return nil; }
  return name;
}

// Caller owns this prefix, has stopped its server and waited for registry flush.
// Never creates system32: font preparation only creates windows/Fonts, so fresh
// prefixes continue through Wine bootstrap. Existing system32 must contain both
// regular PE copies; an incomplete prefix fails without partial repair.
static BOOL LWSyncWineMediaModules(NSString *runtime, NSString *prefix, NSError **error) {
  if (!runtime.isAbsolutePath || !prefix.isAbsolutePath)
    return LWMediaModulesError(error, @"Media module roots must be absolute.");
  int rt = open(runtime.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  int pr = open(prefix.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (rt < 0 || pr < 0) {
    if (rt >= 0) close(rt); if (pr >= 0) close(pr);
    return LWMediaModulesError(error, @"Media module roots must be existing directories without symlinks.");
  }
  __block int windows = -1, unixdir = -1, system = -1;
  NSMutableArray<NSString *> *staged = [NSMutableArray array], *rollback = [NSMutableArray array];
  __block BOOL rollbackFailed = NO;
  __block NSError *syncError = nil;
  BOOL result = (^BOOL {
    NSData *metadata = LWMediaModulesRead(rt, @"runtime.json");
    id parsed = metadata ? [NSJSONSerialization JSONObjectWithData:metadata options:0 error:nil] : nil;
    if (![parsed isKindOfClass:NSDictionary.class] || ![parsed[@"schema"] isEqual:@3])
      return LWMediaModulesError(&syncError, @"Prepared runtime metadata is missing or invalid.");
    id wrapper = parsed[@"media_fix_receipt"];
    id receipt = [wrapper isKindOfClass:NSDictionary.class] ? wrapper[@"receipt"] : nil;
    id modules = [receipt isKindOfClass:NSDictionary.class] ? receipt[@"modules"] : nil;
    NSArray<NSString *> *names = @[@"winegstreamer.dll", @"mfmediaengine.dll"];
    if (![receipt isKindOfClass:NSDictionary.class] || ![receipt[@"schema"] isEqual:@1] || ![modules isKindOfClass:NSDictionary.class] ||
        ![[NSSet setWithArray:[modules allKeys]] isEqual:[NSSet setWithArray:@[@"winegstreamer.dll", @"winegstreamer.so", @"mfmediaengine.dll"]]])
      return LWMediaModulesError(&syncError, @"Runtime needs a complete matching three-module media receipt.");
    for (NSString *name in modules) {
      id h = modules[name];
      if (![h isKindOfClass:NSString.class] || [h length] != 64 ||
          [[h stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"]] length])
        return LWMediaModulesError(&syncError, @"Media receipt contains an invalid digest.");
    }
    windows = LWMediaModulesDirectory(rt, @"wine/lib/wine/x86_64-windows");
    unixdir = LWMediaModulesDirectory(rt, @"wine/lib/wine/x86_64-unix");
    NSMutableArray<NSData *> *selected = [NSMutableArray array];
    for (NSString *name in names) {
      NSData *bytes = LWMediaModulesRead(windows, name);
      if (!bytes || !LWMediaModulesPE(bytes) || ![LWMediaModulesSHA(bytes) isEqual:modules[name]])
        return LWMediaModulesError(&syncError, @"Runtime media PE is missing, invalid, or differs from its receipt.");
      [selected addObject:bytes];
    }
    NSData *unixbytes = LWMediaModulesRead(unixdir, @"winegstreamer.so");
    if (!unixbytes || ![LWMediaModulesSHA(unixbytes) isEqual:modules[@"winegstreamer.so"]])
      return LWMediaModulesError(&syncError, @"Runtime Unix media module differs from the selected PE pair.");
    system = LWMediaModulesDirectory(pr, @"drive_c/windows/system32");
    if (system < 0) {
      if (errno == ENOENT) return YES;
      return LWMediaModulesError(&syncError, @"Private system32 must be a directory without symlinks.");
    }
    NSMutableArray<NSData *> *old = [NSMutableArray array];
    NSMutableArray<NSNumber *> *modes = [NSMutableArray array];
    for (NSString *name in names) {
      NSData *bytes = LWMediaModulesRead(system, name);
      struct stat st;
      if (!bytes || fstatat(system, name.fileSystemRepresentation, &st, AT_SYMLINK_NOFOLLOW) || !S_ISREG(st.st_mode))
        return LWMediaModulesError(&syncError, @"Existing prefix media copies must both be regular files; original prefix was preserved.");
      [old addObject:bytes]; [modes addObject:@(st.st_mode & 0777)];
    }
    // Prestage both replacement and rollback bytes before any visible rename.
    for (NSUInteger i = 0; i < names.count; ++i) {
      if ([old[i] isEqualToData:selected[i]]) { [staged addObject:@""]; [rollback addObject:@""]; continue; }
      NSString *fresh = LWMediaModulesStage(system, selected[i], modes[i].unsignedShortValue);
      if (!fresh) return LWMediaModulesError(&syncError, @"Unable to stage verified media updates; prefix was preserved.");
      [staged addObject:fresh];
      NSString *backup = LWMediaModulesStage(system, old[i], modes[i].unsignedShortValue);
      if (!backup) return LWMediaModulesError(&syncError, @"Unable to stage media rollback; prefix was preserved.");
      [rollback addObject:backup];
    }
    NSUInteger committed = 0;
    BOOL ok = YES;
    for (NSUInteger i = 0; i < names.count; ++i) {
      if (!staged[i].length) { committed = i + 1; continue; }
      // Recheck original bytes and no-follow identity immediately before commit.
      if (![LWMediaModulesRead(system, names[i]) isEqualToData:old[i]] ||
          renameat(system, staged[i].fileSystemRepresentation, system, names[i].fileSystemRepresentation)) { ok = NO; break; }
      committed = i + 1;
      if (![LWMediaModulesRead(system, names[i]) isEqualToData:selected[i]]) { ok = NO; break; }
    }
    if (!ok) {
      for (NSUInteger j = committed; j > 0; --j) {
        NSUInteger i = j - 1;
        if (rollback[i].length && (renameat(system, rollback[i].fileSystemRepresentation, system, names[i].fileSystemRepresentation) ||
            ![LWMediaModulesRead(system, names[i]) isEqualToData:old[i]])) rollbackFailed = YES;
      }
      return LWMediaModulesError(&syncError, rollbackFailed ? @"Media update failed and rollback could not be verified; do not launch this prefix." : @"Media update failed; original prefix media copies were restored.");
    }
    return YES;
  })();
  if (system >= 0) {
    for (NSString *name in staged) if (name.length) unlinkat(system, name.fileSystemRepresentation, 0);
    // Retain any surviving rollback files if restoration could not be verified.
    if (!rollbackFailed) for (NSString *name in rollback) if (name.length) unlinkat(system, name.fileSystemRepresentation, 0);
    close(system);
  }
  if (windows >= 0) close(windows); if (unixdir >= 0) close(unixdir);
  close(rt); close(pr);
  if (!result && error) *error = syncError;
  return result;
}
