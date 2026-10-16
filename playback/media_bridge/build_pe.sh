#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
out="$task_root/build/media-bridge"
toolchain="$task_root/build/toolchains/llvm-mingw-20261006-ucrt-macos-universal"
mkdir -p "$out/include"
/opt/homebrew/bin/python3.13 "$task_root/playback/media_bridge/pe/generate_iids.py" "$out/include/generated-iids.h"
/opt/homebrew/bin/python3.13 "$task_root/playback/media_bridge/pe/generate_traces.py" "$out/include/generated-traces.h"
"$toolchain/bin/x86_64-w64-mingw32-clang" -std=c11 -shared -Wall -Wextra -Wno-incompatible-pointer-types \
  -I"$out/include" "$task_root/playback/media_bridge/pe/lwmedia-winrt.c" \
  "$task_root/playback/media_bridge/pe/lwmedia-winrt.def" \
  -lruntimeobject -lole32 -luuid -o "$out/lwmedia-winrt.dll"
"$toolchain/bin/x86_64-w64-mingw32-clang" -std=c11 -Wall -Wextra -municode \
  -I"$out/include" "$task_root/playback/media_bridge/pe/probe.c" \
  -lruntimeobject -lole32 -luuid -o "$out/lwmedia-contract-probe.exe"
echo "$out/lwmedia-winrt.dll"
