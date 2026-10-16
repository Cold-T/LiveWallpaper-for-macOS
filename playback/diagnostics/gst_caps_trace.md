# Opt-in caps diagnostic

Build the x86_64 diagnostic against the exact personal runtime, without changing
that runtime:

```sh
sh playback/diagnostics/build_gst_caps_trace.sh "$PWD/build/runtime11" "$PWD/build/gst-diagnostics/gst_caps_trace.dylib"
```

For one parent-owned isolated playback experiment, append the diagnostic dylib
to the existing colon-separated DYLD_INSERT_LIBRARIES (keep the desktop bridge),
and set:

```text
LW_GST_CAPS_TRACE=1
LW_GST_CAPS_TRACE_LIMIT=12
```

The limit is per process (1..64, default 12). No constructor initializes Gst.
Only nonfixed caps are logged, with at most 4096 characters and 32 stack frames.
The original caps and video-info arguments are passed unchanged to the original
function, and its return value is returned unchanged. Existing GStreamer
criticals remain visible. No samples, pixels, audio, files or network content
are inspected by the hook. Remove the injected library after the experiment.

The diagnostic links the runtime's libgstvideo/GStreamer/GLib. This makes the
replacee symbol available to dyld before Wine's later dlopen. Darwin interposition
excludes calls to the original from the interposing image; no dlsym lookup in
the replacement can accidentally resolve itself. The direct link does load the
same libraries earlier than usual, so this is a diagnostic environment change
and must not be mixed into timing/performance conclusions.

Native metadata-only fixture validation is recorded in
build/gst-diagnostics/caps-fixture-results.json. It explicitly loads libgstvideo
through dlopen(RTLD_LOCAL) and obtains the conversion function via dlsym. All
three groups (baseline, inserted but disabled, inserted and enabled) returned
fixed=1 and rejected all three nonfixed inputs. The original three criticals
remained in every group, while a limit of two yielded exactly two diagnostic
records. This establishes dlopen/dlsym interception and no recursive replacement
in this runtime; Wine-stack observation remains the parent experiment.

## Current caps warning interpretation

The existing Elaina log has ten startup criticals, but no call stack. The library
precondition returns FALSE on nonfixed caps; it is not an automatic process abort.
Possible Wine callers differ materially:

* wine11-wg_parser.c:134 caps_is_compressed → wg_format_from_caps. This is called
  during decodebin autoplug checks and after gst_pad_query_caps; either can have
  capability sets rather than a concrete negotiated video format.
* wine11-wg_parser.c:812 ACCEPT_CAPS converts candidate and desired formats.
* wine11-wg_transform.c:230 creates a video pool, ignoring conversion failure.
* wine11-wg_transform.c:1235 reads actual output caps and proceeds after failure.

If the stack proves the first path with video/x-raw/audio/x-raw, a semantic fix
is to classify these MIME types as uncompressed without demanding a concrete
GstVideoInfo. If the stack instead shows allocation/output, fix negotiated caps
and propagate failure before using invalid video info. Do not arbitrarily
fixate ranges or force a pixel format; that can change resolution, color or
chroma output. The hook deliberately does not apply either speculative fix.

## Swapchain warning and remaining evidence gap

Local DXMT src/d3d11/d3d11_swapchain.cpp:1119 warns for the requested swap effect
3 and buffer count 2, but then constructs a swapchain and returns S_OK. It does
not reject creation. The same implementation has one retained backbuffer;
GetBuffer at line 255 rejects nonzero indices, GetCurrentBackBufferIndex at
1017 always returns zero, and Present1 at 739 does not apply dirty rectangles
or scroll metadata from its PresentParameters argument.

Effect 3 is FLIP_SEQUENTIAL. Windows guarantees preservation of its backbuffer
contents and consistent buffer indices. Primary API contract:
https://learn.microsoft.com/en-us/windows/win32/api/dxgi/ne-dxgi-dxgi_swap_effect
https://learn.microsoft.com/en-us/windows/win32/api/dxgi/nf-dxgi-idxgiswapchain-getbuffer

Thus this is an acknowledged incomplete emulation path, not proof of incorrect
Elaina pixels. The current log does not show nonzero GetBuffer rejection, but
does not trace each caller's buffer/Present usage either. If the engine renders
every pixel and only uses buffer zero, sampled output may match; reliance on
buffer retention, rotation, partial present, or timing is still unverified.

For parity, obtain the engine's actual GetBuffer/Present calls and compare a
deterministic frame sequence against Windows. A generic fix belongs in DXMT's
sequential-buffer preservation/index/synchronization semantics. Changing the
engine's request to DISCARD or one buffer merely to remove the warning changes
the requested Windows contract and is not established as an equivalent fix.
No runtime or original binary was patched during this investigation.
