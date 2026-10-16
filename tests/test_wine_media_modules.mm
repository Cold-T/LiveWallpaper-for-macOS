#import <Foundation/Foundation.h>
static void alterReadMetadataForTest(int fd);
#define LW_MEDIA_MODULES_TEST_AFTER_READ(fd) alterReadMetadataForTest(fd)
#import "../playback/WineMediaModules.h"
static BOOL changeReadMetadata = NO;
static NSUInteger readMetadataChanges = 0;
static void alterReadMetadataForTest(int fd) {
 if (!changeReadMetadata) return;
 struct stat st; NSCAssert(!fstat(fd,&st), @"read-hook stat");
 struct timespec times[2] = {st.st_atimespec, st.st_mtimespec};
 times[1].tv_sec += 1;
 NSCAssert(!futimens(fd,times), @"read-hook timestamp-only change");
 readMetadataChanges++;
}
#include <stdio.h>
static void check(BOOL ok, NSString *name) { if (!ok) { NSLog(@"FAIL %@", name); abort(); } printf("PASS %s\n", name.UTF8String); }
static NSData *pe(unsigned char marker) {
  NSMutableData *d = [NSMutableData dataWithLength:256]; unsigned char *b = (unsigned char *)d.mutableBytes;
  b[0]='M';b[1]='Z';b[60]=64;memcpy(b+64,"PE\0\0",4);b[68]=0x64;b[69]=0x86;b[86]=0;b[87]=0x20;b[88]=0x0b;b[89]=2;b[255]=marker;return d;
}
static void put(NSString *p, NSData *d) { check([d writeToFile:p atomically:YES], @"fixture write"); }
int main() { @autoreleasepool {
 NSFileManager *fm=NSFileManager.defaultManager;
 NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"lw-media-" stringByAppendingString:NSUUID.UUID.UUIDString]];
 NSString *runtime=[root stringByAppendingPathComponent:@"runtime"], *prefix=[root stringByAppendingPathComponent:@"prefix"];
 NSString *win=[runtime stringByAppendingPathComponent:@"wine/lib/wine/x86_64-windows"], *un=[runtime stringByAppendingPathComponent:@"wine/lib/wine/x86_64-unix"], *sys=[prefix stringByAppendingPathComponent:@"drive_c/windows/system32"];
 for(NSString *p in @[win,un,prefix]) check([fm createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:nil],@"fixture directory");
 NSArray *names=@[@"winegstreamer.dll",@"mfmediaengine.dll"];
 NSData *a=pe(1),*b=pe(2),*before=pe(9),*so=[@"synthetic Unix bytes, receipt-bound" dataUsingEncoding:NSUTF8StringEncoding];
 NSString *meta=[runtime stringByAppendingPathComponent:@"runtime.json"];
 NSMutableDictionary *modules=[@{@"winegstreamer.dll":LWMediaModulesSHA(a),@"mfmediaengine.dll":LWMediaModulesSHA(b),@"winegstreamer.so":LWMediaModulesSHA(so)} mutableCopy];
 void (^receipt)(void)=^{ put(meta,[NSJSONSerialization dataWithJSONObject:@{@"schema":@3,@"media_fix_receipt":@{@"receipt":@{@"schema":@1,@"modules":modules}}} options:0 error:nil]); };
 put([win stringByAppendingPathComponent:names[0]],a);put([win stringByAppendingPathComponent:names[1]],b);put([un stringByAppendingPathComponent:@"winegstreamer.so"],so);receipt();
 NSError *error=nil;
 check(LWSyncWineMediaModules(runtime,prefix,&error),@"fresh prefix defers bootstrap");check(![fm fileExistsAtPath:sys],@"fresh system32 not created");
 // Font preparation's windows/Fonts shape still must not imply system32 exists.
 [fm createDirectoryAtPath:[prefix stringByAppendingPathComponent:@"drive_c/windows/Fonts"] withIntermediateDirectories:YES attributes:nil error:nil];
 check(LWSyncWineMediaModules(runtime,prefix,&error),@"fonts-only prefix defers bootstrap");
 [fm createDirectoryAtPath:sys withIntermediateDirectories:YES attributes:nil error:nil];
 NSString *first=[sys stringByAppendingPathComponent:names[0]],*second=[sys stringByAppendingPathComponent:names[1]];
 put(first,before);put(second,before);
 changeReadMetadata=YES;
 int sourceFD=open(win.fileSystemRepresentation,O_RDONLY|O_DIRECTORY);
 NSData *hydrated=LWMediaModulesRead(sourceFD,names[0]);close(sourceFD);
 check(hydrated && [LWMediaModulesSHA(hydrated) isEqual:modules[names[0]]],@"timestamp changes do not invalidate complete hash-correct bytes");
 check(LWSyncWineMediaModules(runtime,prefix,&error),@"timestamp-changing full runtime combination accepted");
 changeReadMetadata=NO;
 check(readMetadataChanges>=4 && [[NSData dataWithContentsOfFile:first] isEqual:a] && [[NSData dataWithContentsOfFile:second] isEqual:b],@"metadata-only mutations preserve payload and installed hashes");
 put(first,before);put(second,before);
 check(LWSyncWineMediaModules(runtime,prefix,&error),@"old copies updated");check([[NSData dataWithContentsOfFile:first] isEqual:a]&&[[NSData dataWithContentsOfFile:second] isEqual:b],@"complete bytes verified");
 struct stat s1,s2; lstat(first.fileSystemRepresentation,&s1);
 check(LWSyncWineMediaModules(runtime,prefix,&error),@"same copies accepted");lstat(first.fileSystemRepresentation,&s2);check(s1.st_ino==s2.st_ino&&s1.st_mtimespec.tv_sec==s2.st_mtimespec.tv_sec&&s1.st_mtimespec.tv_nsec==s2.st_mtimespec.tv_nsec,@"identical copy never rewritten");
 put(first,before);put(second,before);
 // Validate the complete combination before writing either target.
 NSString *sourceSecond=[win stringByAppendingPathComponent:names[1]];
 [fm removeItemAtPath:sourceSecond error:nil];
 check(!LWSyncWineMediaModules(runtime,prefix,&error),@"missing runtime original refused");check([[NSData dataWithContentsOfFile:first] isEqual:before],@"missing original preserves first");put(sourceSecond,b);
 modules[@"winegstreamer.so"]=LWMediaModulesSHA([NSData data]);receipt();
 check(!LWSyncWineMediaModules(runtime,prefix,&error),@"mismatched Unix pair refused");check([[NSData dataWithContentsOfFile:first] isEqual:before]&&[[NSData dataWithContentsOfFile:second] isEqual:before],@"combination failure writes neither");modules[@"winegstreamer.so"]=LWMediaModulesSHA(so);receipt();
 [modules removeObjectForKey:@"mfmediaengine.dll"];receipt();check(!LWSyncWineMediaModules(runtime,prefix,&error),@"incomplete receipt refused");modules[@"mfmediaengine.dll"]=LWMediaModulesSHA(b);receipt();
 put(sourceSecond,[@"not PE" dataUsingEncoding:NSUTF8StringEncoding]);modules[@"mfmediaengine.dll"]=LWMediaModulesSHA([NSData dataWithContentsOfFile:sourceSecond]);receipt();check(!LWSyncWineMediaModules(runtime,prefix,&error),@"hash-valid malformed PE refused");check([[NSData dataWithContentsOfFile:first] isEqual:before],@"malformed second preserves first");put(sourceSecond,b);modules[@"mfmediaengine.dll"]=LWMediaModulesSHA(b);receipt();
 NSString *outside=[root stringByAppendingPathComponent:@"external.dll"];put(outside,before);
 [fm removeItemAtPath:second error:nil];[fm createSymbolicLinkAtPath:second withDestinationPath:outside error:nil];check(!LWSyncWineMediaModules(runtime,prefix,&error),@"target symlink escape refused");check([[NSData dataWithContentsOfFile:outside] isEqual:before]&&[[NSData dataWithContentsOfFile:first] isEqual:before],@"escape leaves all originals");
 [fm removeItemAtPath:second error:nil];put(second,before);
 [fm removeItemAtPath:sourceSecond error:nil];[fm createSymbolicLinkAtPath:sourceSecond withDestinationPath:outside error:nil];check(!LWSyncWineMediaModules(runtime,prefix,&error),@"runtime source symlink refused");[fm removeItemAtPath:sourceSecond error:nil];put(sourceSecond,b);
 NSString *saved=[prefix stringByAppendingPathComponent:@"saved-system32"];[fm moveItemAtPath:sys toPath:saved error:nil];[fm createSymbolicLinkAtPath:sys withDestinationPath:saved error:nil];check(!LWSyncWineMediaModules(runtime,prefix,&error),@"system32 directory symlink refused");[fm removeItemAtPath:sys error:nil];[fm moveItemAtPath:saved toPath:sys error:nil];
 // Reject metadata symlinks and malformed/missing receipts before any writes.
 NSData *savedMeta=[NSData dataWithContentsOfFile:meta];
 [fm removeItemAtPath:meta error:nil];[fm createSymbolicLinkAtPath:meta withDestinationPath:outside error:nil];
 check(!LWSyncWineMediaModules(runtime,prefix,&error),@"metadata symlink refused");[fm removeItemAtPath:meta error:nil];
 put(meta,[@"{}" dataUsingEncoding:NSUTF8StringEncoding]);check(!LWSyncWineMediaModules(runtime,prefix,&error),@"missing receipt refused");
 put(meta,[@"{\"schema\":3,\"media_fix_receipt\":{\"receipt\":\"wrong type\"}}" dataUsingEncoding:NSUTF8StringEncoding]);check(!LWSyncWineMediaModules(runtime,prefix,&error),@"wrong receipt type refused without exception");
 put(meta,[@"not json" dataUsingEncoding:NSUTF8StringEncoding]);check(!LWSyncWineMediaModules(runtime,prefix,&error),@"malformed metadata refused");put(meta,savedMeta);
 check([[NSData dataWithContentsOfFile:first] isEqual:before]&&[[NSData dataWithContentsOfFile:second] isEqual:before],@"metadata failures preserve both originals");
 [fm removeItemAtPath:second error:nil];check(!LWSyncWineMediaModules(runtime,prefix,&error),@"partial existing prefix fails without repair");check([[NSData dataWithContentsOfFile:first] isEqual:before],@"partial prefix preserves other copy");
 for(NSString *f in [fm contentsOfDirectoryAtPath:sys error:nil]) check(![f hasPrefix:@".lw-media-"],@"no temporary residue");
 [fm removeItemAtPath:root error:nil];printf("Wine prefix media module Foundation regression passed\n");
 }return 0; }
