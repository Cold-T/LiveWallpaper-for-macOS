#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <Carbon/Carbon.h>

// No AppleEvents are sent by inventory, --self-test or --normalize-fixture.
// --snapshot/--command require an explicit --allow-automation flag and an
// already granted Automation permission. Only --request-permission may prompt.
static NSDictionary *Players(void) {
    return @{@"music": @"com.apple.Music", @"spotify": @"com.spotify.client"};
}
static void Emit(id value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:NULL];
    if (!data) data = [@"{\"error\":\"json_serialization\"}" dataUsingEncoding:NSUTF8StringEncoding];
    fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout); fflush(stdout);
}
static OSStatus Permission(NSString *bundle, BOOL ask) {
    NSData *utf8 = [bundle dataUsingEncoding:NSUTF8StringEncoding];
    AEAddressDesc target = {typeNull, NULL};
    OSStatus result = AECreateDesc(typeApplicationBundleID, utf8.bytes, utf8.length, &target);
    if (!result) {
        result = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask);
        AEDisposeDesc(&target);
    }
    return result;
}
static BOOL IsRunning(NSString *bundle) {
    return [NSRunningApplication runningApplicationsWithBundleIdentifier:bundle].count > 0;
}
static NSDictionary *Inventory(void) {
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *key in @[@"music", @"spotify"]) {
        NSString *bundle = Players()[key];
        NSURL *url = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:bundle];
        [items addObject:@{@"player": key, @"bundleIdentifier": bundle,
                           @"installed": @(url != nil), @"running": @(IsRunning(bundle))}];
    }
    return @{@"schemaVersion": @1, @"type": @"inventory", @"players": items,
             @"backend": @"applescript-per-player", @"globalSessionEnumeration": @NO};
}
static NSString *DString(NSAppleEventDescriptor *d, NSInteger index) {
    return [d descriptorAtIndex:index].stringValue ?: @"";
}
static double DNumber(NSAppleEventDescriptor *d, NSInteger index) {
    NSAppleEventDescriptor *v = [[d descriptorAtIndex:index] coerceToDescriptorType:typeIEEE64BitFloatingPoint];
    double x = 0;
    if (v.data.length == sizeof(x)) [v.data getBytes:&x length:sizeof(x)];
    return isfinite(x) ? x : 0;
}
// Canonical source-independent normalization is shared by live and fixture paths.
static NSDictionary *Normalize(NSDictionary *input) {
    NSString *bundle = input[@"bundleIdentifier"];
    if (![bundle isKindOfClass:NSString.class] || !bundle.length)
        return @{@"error": @"invalid_bundle_identifier"};
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"title", @"artist", @"album", @"artworkURL", @"artworkMimeType", @"artworkBase64"])
        if ([input[key] isKindOfClass:NSString.class]) r[key] = input[key];
    r[@"id"] = bundle; r[@"bundleIdentifier"] = bundle;
    NSString *state = input[@"state"];
    r[@"state"] = [@[@"playing", @"paused", @"stopped"] containsObject:state] ? state : @"unknown";
    for (NSString *key in @[@"durationSeconds", @"positionSeconds"])
        if ([input[key] isKindOfClass:NSNumber.class] && isfinite([input[key] doubleValue]))
            r[key] = @(MAX(0, [input[key] doubleValue]));
    r[@"observedUnixSeconds"] = [input[@"observedUnixSeconds"] isKindOfClass:NSNumber.class]
        ? input[@"observedUnixSeconds"] : @(NSDate.date.timeIntervalSince1970);
    r[@"capabilities"] = input[@"capabilities"] ?: @{};
    r[@"source"] = @"applescript-per-player";
    return r;
}
static NSDictionary *Snapshot(NSString *player) {
    NSString *bundle = Players()[player];
    if (!bundle) return @{@"error": @"unsupported_player"};
    if (!IsRunning(bundle)) return @{@"player":player, @"available":@NO, @"reason":@"not_running"};
    OSStatus permission = Permission(bundle, NO);
    if (permission) return @{@"player":player, @"available":@NO, @"reason":@"automation_permission_required", @"osStatus":@(permission)};
    // Explicit terms are compiled in the source so AppleScript does not need to
    // retrieve the application's terminology at runtime. Application is running.
    NSString *script;
    if ([player isEqualToString:@"music"]) {
        script = @"tell application id \"com.apple.Music\"\n"
            "set s to player state as string\nif s is \"stopped\" then return {s, \"\", \"\", \"\", 0, 0, missing value}\n"
            "set t to current track\nset a to missing value\ntry\nset a to raw data of artwork 1 of t\nend try\n"
            "return {s, name of t, artist of t, album of t, duration of t, player position, a}\nend tell";
    } else {
        script = @"tell application id \"com.spotify.client\"\n"
            "set s to player state as string\nif s is \"stopped\" then return {s, \"\", \"\", \"\", 0, 0, \"\"}\n"
            "set t to current track\nreturn {s, name of t, artist of t, album of t, (duration of t) / 1000, player position, artwork url of t}\nend tell";
    }
    NSDictionary *error = nil;
    NSAppleEventDescriptor *d = [[[NSAppleScript alloc] initWithSource:script] executeAndReturnError:&error];
    if (!d || error) return @{@"player": player, @"available": @NO, @"reason": @"apple_event_failed", @"details": error.description ?: @"No result"};
    NSMutableDictionary *raw = [@{@"bundleIdentifier":bundle, @"state":DString(d,1),
        @"title":DString(d,2), @"artist":DString(d,3), @"album":DString(d,4),
        @"durationSeconds":@(DNumber(d,5)), @"positionSeconds":@(DNumber(d,6)),
        @"capabilities":@{@"play":@YES,@"pause":@YES,@"toggle":@YES,@"next":@YES,@"previous":@YES,@"seek":@YES}}
        mutableCopy];
    if ([player isEqualToString:@"music"]) {
        NSAppleEventDescriptor *art = [d descriptorAtIndex:7];
        if (art.descriptorType != typeType && art.data.length > 4 && art.data.length <= 16*1024*1024) {
            const unsigned char *b=art.data.bytes;
            NSString *mime = (b[0]==0xff && b[1]==0xd8) ? @"image/jpeg" : (b[0]==0x89 && b[1]=='P') ? @"image/png" : nil;
            if (mime) { raw[@"artworkBase64"]=[art.data base64EncodedStringWithOptions:0]; raw[@"artworkMimeType"]=mime; }
        }
    } else {
        // Spotify returns an actual URL. Network fetching is deliberately separate:
        // no implicit network request, fake cover, or claim that bytes are available.
        NSString *url=DString(d,7); if ([url hasPrefix:@"https://"]) raw[@"artworkURL"]=url;
    }
    return @{@"player":player,@"available":@YES,@"session":Normalize(raw)};
}
static int Command(NSString *player, NSString *command, NSString *argument) {
    NSString *bundle=Players()[player];
    if (!bundle || !IsRunning(bundle)) { Emit(@{@"ok":@NO,@"error":@"player_not_running"}); return 3; }
    OSStatus permission=Permission(bundle,NO);
    if (permission) { Emit(@{@"ok":@NO,@"error":@"automation_permission_required",@"osStatus":@(permission)}); return 4; }
    NSDictionary *allowed=@{@"play":@"play",@"pause":@"pause",@"toggle":@"playpause",@"next":@"next track",@"previous":@"previous track"};
    NSString *statement=allowed[command];
    if ([command isEqualToString:@"seek"]) {
        NSScanner *scanner=[NSScanner scannerWithString:argument ?: @""]; double pos;
        if (![scanner scanDouble:&pos] || !scanner.isAtEnd || !isfinite(pos) || pos<0) { Emit(@{@"ok":@NO,@"error":@"invalid_position"}); return 2; }
        statement=[NSString stringWithFormat:@"set player position to %.9f",pos];
    }
    if (!statement) { Emit(@{@"ok":@NO,@"error":@"unsupported_command"}); return 2; }
    NSString *script=[NSString stringWithFormat:@"tell application id \"%@\" to %@",bundle,statement];
    NSDictionary *error=nil;
    [[[NSAppleScript alloc] initWithSource:script] executeAndReturnError:&error];
    Emit(@{@"ok":@(error==nil),@"acknowledgement":@"apple_event_completion",@"error":error ? error.description : (id)NSNull.null});
    return error ? 5 : 0;
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        NSMutableArray<NSString *> *args=[NSMutableArray array];
        for(int i=1;i<argc;i++) [args addObject:@(argv[i])];
        NSString *mode=args.firstObject ?: @"--inventory";
        NSString *(^value)(NSString *) = ^NSString *(NSString *flag) { NSUInteger i=[args indexOfObject:flag]; return i!=NSNotFound && i+1<args.count ? args[i+1] : nil; };
        if ([mode isEqualToString:@"--inventory"]) { Emit(Inventory()); return 0; }
        if ([mode isEqualToString:@"--normalize-fixture"]) {
            NSData *data=[NSData dataWithContentsOfFile:args.count>1 ? args[1] : @""];
            id input=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            if (![input isKindOfClass:NSDictionary.class]) { Emit(@{@"error":@"invalid_fixture"}); return 2; }
            Emit(Normalize(input)); return 0;
        }
        if ([mode isEqualToString:@"--self-test"]) {
            NSDictionary *r=Normalize(@{@"bundleIdentifier":@"fixture.test",@"state":@"playing",@"title":@"音乐 🎵",@"positionSeconds":@(-3),@"observedUnixSeconds":@0});
            BOOL ok=[r[@"title"] isEqual:@"音乐 🎵"] && [r[@"positionSeconds"] doubleValue]==0 && [r[@"state"] isEqual:@"playing"];
            Emit(@{@"ok":@(ok),@"scope":@"fixture_normalization_only",@"appleEventsSent":@0}); return ok ? 0 : 1;
        }
        if ([mode isEqualToString:@"--request-permission"]) {
            NSString *bundle=Players()[value(@"--player")];
            if (!bundle) { Emit(@{@"error":@"explicit_player_required"}); return 2; }
            OSStatus result=Permission(bundle,YES);
            Emit(@{@"granted":@(result==0),@"osStatus":@(result)}); return result ? 4 : 0;
        }
        if (![args containsObject:@"--allow-automation"]) {
            Emit(@{@"error":@"explicit_allow_automation_flag_required",@"appleEventsSent":@0}); return 4;
        }
        NSString *player=value(@"--player");
        if ([mode isEqualToString:@"--snapshot"] && player) { Emit(Snapshot(player)); return 0; }
        if ([mode isEqualToString:@"--command"] && player) return Command(player,args.count>1?args[1]:nil,value(@"--position"));
        Emit(@{@"error":@"invalid_command",@"supported":@[@"--inventory",@"--snapshot --player music|spotify --allow-automation",@"--request-permission --player music|spotify",@"--self-test"]}); return 2;
    }
}
