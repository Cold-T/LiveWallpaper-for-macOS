# Experimental Wine 11 MF source scheduling patch

Independent candidate only. This is not connected to the product build or
runtime deployment. It has not been executed in Wine by its author.

The observed failure: one MF source STANDARD work queue (max1worker) remains
inside an audio `wait_on_sample`; a video request queued behind it is never
invoked, while renderer particles/clocks, SAR waits and protected native output
callbacks continue. See the archived Hoshino trace and analysis under
`build/video-black-investigation/hoshino-mf-clock-trace-1/static-clock-analysis/`.

## Patch bases and licensing

`wine-11.0-mf-source-nonblocking.patch` is the **complete patch against pristine
upstream Wine11.0**, official tag commit
`db11d0fe6a169c457e23d007e20404643d067aa8`, source archive SHA256
`f09e8153aa46a581d2b56a5b1363b04832070b9409d9244a68cf482b243ff14a`.
It includes the earlier raw-caps MIME classification fix and the MF scheduling
changes. Apply once to pristine upstream; do not also apply the raw-caps patch.

The current analysis baseline `/private/tmp/wine-wine-11.0` already has the
raw-caps fix. `build/wine-mf-fix/mf-nonblocking-source.patch` is the MF-only delta
against that baseline; `wine-11.0-raw-caps-base.patch` records its relationship
to pristine upstream. The full patch was applied to five pristine archive files
and all five resulting hashes match the frozen source exactly; see
`build/wine-mf-fix/patch-application-check.json`.

The original Wine/GStreamer source notices remain in the patch targets.
Wine-derived changes and the associated synthetic fixture are provided under
LGPL2.1-or-later; the complete license is `WINE-COPYING.LIB`. Existing upstream
copyright notices are retained. The source archive is from upstream Wine; this
is not a claim that Sikarugir/Gcenx vendor source or every private ABI is identical.

## Design

Keep the existing serial source control queue. Accepted sample commands own
strong references to stream/token and join a logical FIFO per stream. One pump
per stream performs a finite nonblocking attempt; empty input schedules one
cancellable1ms retry, never blocks the control worker. A timer callback only
posts another pump onto the source queue.

The new Unix call is appended at index37; all original37slots are unchanged,
new count38. It distinguishes READY/WOULD_BLOCK/NEED_BUFFER/EOS/CANCELLED/ERROR.
Preflight metadata is advisory, **not a buffer loan**. The actual read validates
stream epoch, copies into the caller's capacity, refreshes actual metadata and
releases the same buffer under one parser mutex. Asynchronous Gst flush cannot
replace the buffer between copy and release. Capacity failure never consumes;
Gst fatal error with empty input reports ERROR instead of retrying forever.

Stop/seek invalidate source epoch and pending work, so old tasks do not read new
segment data. Pause retains FIFO tokens, cancels retries; resume re-arms after
state transition. Timer serial numbers reject an already-delivered stale retry.
Shutdown cancels logical work before disconnect/free; outstanding tasks own
stream lifetime and check terminal state before any native read. Scheduling
failure clears pending work and emits MF MEError. No stream is discarded merely
to unstick playback; no caps, samples, clock rates, video PTS, swap effect or
framebuffer dimensions are rewritten.

## Frozen artifacts and checks

- PE `/private/tmp/lw-wine-mf-build/winegstreamer-mf-candidate.dll`,2322432bytes,
  SHA256 `a022ef0643aaf78d4eec35517d280e2664526b9c5e95f7a3224d91cc765850df`.
  AMD64 PE32+, normal Wine builtin DLL; not Authenticode signed.
- Unix `/private/tmp/lw-wine-mf-build/winegstreamer-mf-candidate.so`,211616bytes,
  SHA256 `d4e6e00c874ceb0f89ccabd3691c508499c443daa23979ef976a0a98e0e9d84a`.
  x86_64/minimum macOS14/SDK27, ad-hoc signed; codesign strict verification passed.
- Native synthetic fixture executes the **actual new function body**, extracted
  unchanged from source, against synthetic GstBuffers and a minimal parser field
  model.11checks pass: empty/EOS/disabled/flushing/fatalerror, preflight/capacity,
  inter-call epoch change, exact bytes/PTS/duration, consume-once. No media,
  pipelines, audio output, GUI or Wine. This is not full MF scheduler/ABI testing.
- Win64 parameter48bytes, Win32 parameter40bytes; index/count and offsets checked
  by actual x86_64 and i686 LLVM-mingw C_ASSERT compilation (not PE execution).
  Complete32bit PE module was not built or tested.
- Six PE export names/ordinals match the selected vendor DLL; added imports are
  only MFCancelWorkItem and MFScheduleWorkItem, both present in runtime mfplat.
  Unix251undefined symbols exactly match the prior audited native candidate;
  dependencies use Gst ABI2802 and GLib/GObject8201. This checks import surfaces,
  not complete vendor semantic compatibility.

Only the matching PE+Unix pair may exercise the appended call. **Do not deploy
just the Unix module or combine new PE with an old37slot Unix module.** No runtime
files, registry or product deployment policy were modified here. Parent controls
any isolated, backed-up A/B and restoration.

## Offline build reproduction

```
playback/patches/build-mf-source-candidate.sh /private/tmp/lw-wine11.tar.gz
```

Requires only already available CLT/SDK, extracted LLVM-mingw toolchain, Bison3.8.2,
GStreamer development headers and matching runtime libraries. Defaults reference
the investigation's `/private/tmp` dependencies; override `LW_MF_TOOLS`,
`LW_MF_SDK`, `LW_MF_BISON`, `LW_MF_GST_SDK`, `LW_MF_GLIB_CONFIG`, `LW_MF_GST_LIB`,
`LW_MF_PYTHON` as needed. A caller-specified `LW_MF_WORK_ROOT` must not exist.
No downloads, installation or runtime replacement is performed. Keep dependency
flag paths without spaces for the Wine configure flags. The script builds real
Windows PE with LLVM-mingw; it does not use `--without-mingw` or fake
`ac_cv_mabi_ms=yes`. It runs native-only tests and compiles both ABI fixtures.
No Wine, Wineboot, server, GUI or real media is executed.

The final Unix link uses `mf-source-ntdll-interface.tbd`, an import interface for
only the two preexisting ntdll imports, not copied ntdll implementation code.
Rebuild byte hashes may differ due to timestamps, paths and signing; frozen
hashes above identify the exact reviewed candidate. The standalone script was
syntax checked; actual configure/compile/link/sign/test commands were performed
in `/private/tmp/lw-wine-mf-build`, with logs retained there.

## Remaining gates

Real Stop/seek/Pause/resume/loop/Shutdown event ordering, reference balance,
work-queue lifetime,1ms retry CPU cost and long video/scene fidelity remain
unverified. A successful first background frame is not sufficient. Run the
same original source and quality, protected mute path and bounded observation,
check sustained video sample PTS/progress and clean shutdown, then exercise
control transitions and restore both modules. The original frame sink may
intentionally drop already-late frames; this patch does not claim that every
source60fps frame can be presented at desktop15fps.
