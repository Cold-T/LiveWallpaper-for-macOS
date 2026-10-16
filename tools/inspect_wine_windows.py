#!/usr/bin/env python3
"""Read window metadata for this probe and desktop layers; never capture pixels."""
import ctypes as C
from datetime import datetime, timezone
import json
from pathlib import Path
import plistlib
import sys

cg = C.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
cf = C.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
cg.CGWindowListCopyWindowInfo.argtypes = [C.c_uint32, C.c_uint32]
cg.CGWindowListCopyWindowInfo.restype = C.c_void_p
cg.CGWindowLevelForKey.argtypes = [C.c_int32]
cg.CGWindowLevelForKey.restype = C.c_int32
cf.CFPropertyListCreateData.argtypes = [C.c_void_p, C.c_void_p, C.c_long, C.c_ulong, C.c_void_p]
cf.CFPropertyListCreateData.restype = C.c_void_p
cf.CFDataGetLength.argtypes = [C.c_void_p]
cf.CFDataGetLength.restype = C.c_long
cf.CFDataGetBytePtr.argtypes = [C.c_void_p]
cf.CFDataGetBytePtr.restype = C.c_void_p
cf.CFRelease.argtypes = [C.c_void_p]
windows = cg.CGWindowListCopyWindowInfo(1, 0)
if not windows:
    raise SystemExit('WindowServer metadata unavailable')
data = cf.CFPropertyListCreateData(None, windows, 100, 0, None)
if not data:
    cf.CFRelease(windows)
    raise SystemExit('WindowServer metadata serialization unavailable')
try:
    rows = plistlib.loads(C.string_at(cf.CFDataGetBytePtr(data), cf.CFDataGetLength(data)))
    relevant = []
    for row in rows:
        owner = row.get('kCGWindowOwnerName', '')
        title = row.get('kCGWindowName', '')
        if not title.startswith('LiveWallpaper-Wine-') and owner not in ['Finder', 'Wallpaper', 'LiveWallpaper', 'WindowManager', 'Notification Center', 'LiveWallpaperWinePlayer']:
            continue
        if not title.startswith('LiveWallpaper-Wine-') and row.get('kCGWindowLayer', 0) >= 0:
            continue
        item = {key: row.get(key) for key in ['kCGWindowOwnerName', 'kCGWindowOwnerPID',
            'kCGWindowNumber', 'kCGWindowLayer', 'kCGWindowBounds', 'kCGWindowIsOnscreen']}
        if title.startswith('LiveWallpaper-Wine-'):
            item['kCGWindowName'] = title
        relevant.append(item)
    result = {'time': datetime.now(timezone.utc).isoformat(),
              'order': 'front-to-back, onscreen windows only',
              'standard_levels': {name: cg.CGWindowLevelForKey(key) for name, key in
                                  [('desktop', 2), ('desktopIcon', 18), ('normal', 4)]},
              'windows': relevant}
    output = json.dumps(result, indent=2, ensure_ascii=False)
    if len(sys.argv) > 1:
        Path(sys.argv[1]).write_text(output)
    print(output)
finally:
    cf.CFRelease(data)
    cf.CFRelease(windows)
