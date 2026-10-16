> v18 update: use release-candidate-schema1.json for the selected triplet. The older selection below predates color-format-transfer.patch and is retained as historical validation.

# Final integration checklist, current source inspection

No runtime/prefix or product source changed in this audit. No Wine executed.

## Selected release candidate

`release-candidate-schema1.json` is accepted by the existing preparer's exact
three-module verifier. Physical artifacts were hash-verified:

| Module | Physical candidate | SHA256 |
| --- | --- | --- |
| winegstreamer.dll | /private/tmp/lw-wine-source-pool-build/winegstreamer-mf-candidate.dll | df9ce17519d944f68001e47ea4a16560b4f29e916bc9d13b0d712561c805a5ad |
| winegstreamer.so | /private/tmp/lw-wine-source-pool-build/winegstreamer-mf-candidate.so | d4e6e00c874ceb0f89ccabd3691c508499c443daa23979ef976a0a98e0e9d84a |
| mfmediaengine.dll | /private/tmp/lw-wine-loop-v3-build/mfmediaengine-loop-v3-candidate.dll | 2494d7755159acf4a25ed59fd8175a62e4c94b4123594a57e65f5ab61a8c3560 |

This uses stable CPU output cache + source pool and loop v3, without direct
staging/stride repair. Source PE retains low-noise diagnostic counters; product
`WinePlayback.h` already uses `WINEDEBUG=-all,err+all`, suppressing trace output.
There is no new fully timing-free source PE build. Avoid claiming otherwise.

The actual near-realtime product evidence used the same source PE/Unix with
**timing** MediaEngine a3ea3fc... rather than this release MediaEngine2494d775...
(the latter preserves v3 functional control code without timing). Exact final
triplet acceptance therefore remains a gate. The descriptive
`three-module-receipt.json` intentionally records the actual diagnostic triplet;
it is not the schema1 preparation input.

## Reproduce

```
LW_MF_RELEASE_LOOP=1 playback/patches/source-pool-package/build.sh /private/tmp/lw-wine11.tar.gz
```

The default build reproduces the diagnostic MediaEngine source. Release mode
additionally applies `release-mediaengine-delta.patch`; all three resulting
MediaEngine files match the frozen v3 source hashes. All12 full-patch files were
verified against pristine Wine11 archive application. Source copies, source
manifests and both patch checks are retained. Script syntax passes; complete
fresh configure/build invocation has not been run, and output hashes need not
match old timestamp/path-bearing artifacts. Existing frozen modules themselves
were built and linked successfully.

## Minimal preparation changes

`tools/prepare_wine_runtime.py` already accepts/validates every selected module
and a schema1 receipt. No loader/COM/product source change is required merely
to select this combination. Use the existing preparation arguments with a
**fresh output runtime** plus:

```
--wine-gstreamer-pe /private/tmp/lw-wine-source-pool-build/winegstreamer-mf-candidate.dll
--wine-gstreamer-pe-sha256 df9ce17519d944f68001e47ea4a16560b4f29e916bc9d13b0d712561c805a5ad
--wine-gstreamer-unix /private/tmp/lw-wine-source-pool-build/winegstreamer-mf-candidate.so
--wine-gstreamer-sha256 d4e6e00c874ceb0f89ccabd3691c508499c443daa23979ef976a0a98e0e9d84a
--media-engine-pe /private/tmp/lw-wine-loop-v3-build/mfmediaengine-loop-v3-candidate.dll
--media-engine-pe-sha256 2494d7755159acf4a25ed59fd8175a62e4c94b4123594a57e65f5ab61a8c3560
--media-fix-receipt playback/patches/source-pool-package/release-candidate-schema1.json
--no-video-hardware-acceleration
```

The real invocation also requires existing engine/Wine/fallback/GStreamer,
DXMT/framework/bridge inputs and fresh `--output`; this list is only the media
selection additions. The reviewed receipt enables `videoframework=mf`; explicit
HWA false reproduces the successful software-decoding/DXMT output path.
Original Windows EXE bytes remain unchanged. Preparation records selected
hashes under runtime.json; do not use the old
`playback/patches/wine-11.0-media-fix-v3.json`, which selects the old source PE.

`playback/WinePlayback.h` checks media module existence and launches the prepared
WinePlayer app. `playback/WineCompatibility.h` currently preserves these video
backend choices, so no conflicting runtime policy was found. It still disables
`mediaintegration`, a separate unresolved Windows.Media.Control parity feature;
this video package does not complete global media controls.

Use a fresh app-owned acceptance state/prefix (LIVEWALLPAPER_WINE_STATE) or audit
existing system32 module hashes while stopped: `playback/WinePrefix.h` handles
Retina only and has no explicit media-module migration. Existing prefixes can
contain earlier copied builtin PE modules. Never assume swapping the canonical
runtime updates an old system32 copy, and never overwrite an active prefix.

`tools/build_wine_preview.py` packages playback/tools sources, but does **not**
bundle the prepared runtime. Select the resulting runtime in the app's settings
or LIVEWALLPAPER_WINE_RUNTIME. Rebuild the app only if other native product
sources changed; this media selection alone doesn't require a Swift/ObjC edit.
Retain LGPL source/patch/license materials when distributing modified Wine.

## Acceptance before promotion

Already recorded: dual-arch13 native buffer checks with sanitizers;16 real
Wine/MF sample/payload/lifetime contract checks; actual first product1199video
samples19.928s source wall,20.540s engine span for19.983s author duration;
1allocation/1198reuse/active0/one12,441,600byte idle buffer. Near realtime is not
a zero-dropped-frame/every-wallpaper equivalence claim.

Still needed: exact final three-module product launch; no-pause multi-loop speed
and stable memory, more wallpaper/video formats and simultaneous streams,
Pause/resume/seek/stop/clean restart controls. Separate explicitly paused loops
from speed measurements. Verify final runtime and loaded module hashes, original
EXE hash, clean process shutdown and artifact receipt before promotion.
