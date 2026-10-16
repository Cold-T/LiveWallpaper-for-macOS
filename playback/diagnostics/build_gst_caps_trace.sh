#!/bin/sh
set -eu
# Build only; never start Wine or install anything. Pass the prepared runtime.
runtime=${1:?Usage: build_gst_caps_trace.sh ABSOLUTE_RUNTIME [OUTPUT_DYLIB]}
output=${2:-build/gst-diagnostics/gst_caps_trace.dylib}
case "$runtime" in /*) ;; *) echo 'Runtime must be absolute' >&2; exit 2;; esac
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
gst_lib="$runtime/Frameworks/GStreamer.framework/Versions/1.0/lib"
mkdir -p "$(dirname -- "$output")"
/Library/Developer/CommandLineTools/usr/bin/clang \
  -arch x86_64 -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
  -mmacosx-version-min=14.0 -std=c11 -dynamiclib -Wall -Wextra \
  "$script_dir/gst_caps_trace.c" -L"$gst_lib" \
  -lgstvideo-1.0 -lgstreamer-1.0 -lglib-2.0 \
  -Wl,-rpath,"$gst_lib" -o "$output"
