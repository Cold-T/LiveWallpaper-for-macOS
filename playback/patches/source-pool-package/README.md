# Wine 11 MF media fixes: reproducible cache + source-pool candidate

Experimental combination matching the parent's actually tested product launch.
Not promoted until no-pause multi-loop and other-wallpaper regression completes.
The original Wallpaper Engine Windows executable and author assets are unchanged.

The complete `wine11-cache-pool-loop.patch` applies **once to pristine upstream
Wine 11.0**, tag commit `db11d0fe6a169c457e23d007e20404643d067aa8`, archive
SHA256 `f09e8153aa46a581d2b56a5b1363b04832070b9409d9244a68cf482b243ff14a`.
Do not layer the old raw-caps, nonblocking-source, output-cache or loop patches
on top: all are included. All 12 output source files were applied from that
archive and independently hash-checked against frozen corresponding sources;
see `patch-application-check.json` and `source-manifest.json`. Exact source
copies are retained here so the investigation's temporary directories are not
required to retain the patch source.

The combination contains:

- Raw Gst caps MIME classification without requiring fixed raw caps.
- Source per-stream logical FIFO/nonblocking pump, cancellable retry and atomic
  Unix preflight/read epoch validation, appended Unix slot37 (38 total).
- CPU output write-only scratch/cache, complete-frame commit after success;
  avoids downloading the old output GPU texture before overwriting it.
- Source raw-video private standard IMFMediaBuffer with16byte payload alignment,
  full-copy-before-publication seal, last-COM-ref reuse, at most2idle cached
  allocations/64MiB per stream. Audio retains the original MF buffer factory.
- MediaEngine loop v3 and explicit-new-segment sink EOS/pending reset, preserving
  existing in-flight seek targets. Pause/current-position resume does not invent
  a new segment.
- Existing perloop/batch diagnostic timing, deliberately retained to reproduce
  the tested combination. No timing-free release build has been certified.

**Excluded:** direct D3D staging candidates, output-stride repair v3/v4, shader
changes, author-video conversion, playback-rate or frame-dropping changes.
`three-module-receipt.json` identifies the exact three tested binary hashes.
Only use the matching PE/Unix pair; a new PE calling slot37 must never use the
old37-slot Unix library. The MediaEngine loop module is the third module.

## Build, without running Wine or installing anything

```
playback/patches/source-pool-package/build.sh /private/tmp/lw-wine11.tar.gz
```

Use a fresh `LW_MF_WORK_ROOT` if specifying a destination. Defaults and dependency
overrides follow `../README-mf-source.md`: physical LLVM-mingw, CLT/macOS SDK,
Bison3.8.2, matching Gst development headers/runtime libraries. The archive hash
is checked, source extracted fresh, patch applied, both Wine DLLs and the Unix
module compiled. The final Unix module is linked against the checked ntdll
import-interface stub and ad-hoc signed/strict verified. Native synthetic parser
checks and actual Win64/i686 compile-time ABI checks run; no Wine process, GUI,
audio output, media pipeline or runtime replacement occurs.

The script was syntax-checked; clean archive application and final source hashes
were actually verified. The complete new fresh configure/build invocation has
not yet been executed. Corresponding individual candidate compile/link/test
commands were executed in physical investigation build directories. Rebuilt
binary bytes may differ because of paths/timestamps/signatures; compare source
and ABI rather than claiming a deterministic binary match.

## Actual validation and limits

Parent executed `source-buffer-contract.exe` in an isolated Wine prefix: exit0,
16 named checks true. Real MFStartup/MFCreateSample/AddBuffer/length/contiguous
buffer/removal and retained payload lifetime after pool close passed, using48
synthetic bytes. This validates real MF buffer integration, not a real media
source by itself. Full stdout/stderr (including Wine mmap diagnostics) are in
`build/wine-mf-fix/source-pool/real-mf-buffer-contract.json`.

Actual product case `hoshino-product-source-pool-1` first video loop delivered
1199 samples, first-to-last source wall19.928s; MediaEngine Tick span20.540s for
the author's19.983s clip at rate1. Pool allocated once, reused1198 times, ended
with active0/one cached12,441,600byte buffer. This is a substantial improvement
from stable cache23–28s and the earlier~55s source/conversion path. The remaining
~0.56s overhead means this evidence is **near realtime**, not a proof of exact
rate parity or zero dropped presentation frames. See source-pool's
`first-product-loop-evidence.json` for literal log lines and indices. Later
loops in that case include parent-requested pauses and must be read separately.

Native buffer tests separately pass on ARM64 and x86_64/Rosetta with ASan/UBSan,
including four-thread retained reference/read versus close. Real arbitrary
consumer compatibility, long-session memory, multiple simultaneous4K videos,
device changes and further wallpaper regressions remain release gates. No test
success here permits silently replacing the frozen test combination.

Wine-derived changes and new associated code use LGPL-2.1-or-later; upstream
copyright notices remain in the source. See `../WINE-COPYING.LIB`. This records
upstream-based compatible components, not a claim to reproduce every vendor
private patch or redistribution permission for the proprietary engine.

## Release selection audit

See `FINAL-INTEGRATION.md` for existing product/preparer hooks and remaining acceptance gates. `LW_MF_RELEASE_LOOP=1 build.sh` selects the separately audited non-timing loop-v3 source. `release-candidate-schema1.json` is the machine input for the current preparer; the descriptive three-module receipt above records the actual timing-enabled test. Do not conflate them.

## v18 color transfer

Apply `color-format-transfer.patch` after the combined patch and optional release delta (build.sh does this). It prevents raw BGRA-to-RGBA GPU copies; the existing shader converts semantic colors. A same-format GPU copy fills that shader source without CPU texture readback. Captured actual formats: output87/source87/destination28. Original asset/reference and actual desktop visualization confirmed normal skin, silver-blue hair, blue book, warm background; 70-second muted regression passed. Earlier validation files describe pre-color builds. The current selected release triplet is release-candidate-schema1.json.
