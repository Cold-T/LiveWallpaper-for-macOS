#!/bin/sh
# Offline, isolated Wine11 candidate build. Never installs or runs Wine.
# Wine-derived patch: LGPL-2.1-or-later; see README-mf-source.md.
set -eu
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_DIR=$(CDPATH= cd "$SCRIPT_DIR/../.." && pwd)
ARCHIVE=${1:?Usage: build-mf-source-candidate.sh /path/to/wine-wine-11.0.tar.gz}
EXPECTED=f09e8153aa46a581d2b56a5b1363b04832070b9409d9244a68cf482b243ff14a
ACTUAL=$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')
[ "$ACTUAL" = "$EXPECTED" ] || { echo 'Wine archive hash mismatch' >&2; exit 2; }
TOOLS=${LW_MF_TOOLS:-/private/tmp/lw-llvm-mf-tools}
SDK=${LW_MF_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk}
GSTREAMER_SDK=${LW_MF_GST_SDK:-/private/tmp/lw-gst-sdk}
GLIB_CONFIG=${LW_MF_GLIB_CONFIG:-/private/tmp/glib/2.82.1/lib/glib-2.0/include}
GSTREAMER_LIB=${LW_MF_GST_LIB:-$REPO_DIR/build/runtime11/Frameworks/GStreamer.framework/Versions/1.0/lib}
BISON_ROOT=${LW_MF_BISON:-/private/tmp/bison-3.8.2}
for f in "$TOOLS/bin/x86_64-w64-mingw32-clang" "$TOOLS/bin/i686-w64-mingw32-clang" "$BISON_ROOT/src/bison" "$SDK/usr/include/stdio.h" "$GSTREAMER_SDK/include/gstreamer-1.0/gst/gst.h" "$GLIB_CONFIG/glibconfig.h"; do
  [ -f "$f" ] || { echo "Missing existing dependency: $f" >&2; exit 3; }
done
if [ -n "${LW_MF_WORK_ROOT:-}" ]; then
  WORK=$LW_MF_WORK_ROOT
  [ ! -e "$WORK" ] || { echo 'LW_MF_WORK_ROOT must be fresh' >&2; exit 4; }
  mkdir -p "$WORK"
else
  WORK=$(/usr/bin/mktemp -d /private/tmp/lw-wine-mf-repro.XXXXXX)
fi
mkdir "$WORK/source" "$WORK/build" "$WORK/tests"
/usr/bin/tar -xzf "$ARCHIVE" -C "$WORK/source" --strip-components=1
(cd "$WORK/source" && /usr/bin/patch -p1 < "$SCRIPT_DIR/wine-11.0-mf-source-nonblocking.patch")
export PATH="$TOOLS/bin:/Library/Developer/CommandLineTools/usr/bin:/usr/bin:/bin"
export CC='/Library/Developer/CommandLineTools/usr/bin/clang -arch x86_64'
export CXX='/Library/Developer/CommandLineTools/usr/bin/clang++ -arch x86_64'
export CPPFLAGS="-isysroot $SDK"
export CFLAGS="-O2 -mmacosx-version-min=14.0 -isysroot $SDK"
export CXXFLAGS="$CFLAGS -stdlib=libc++ -isystem $SDK/usr/include/c++/v1"
export LDFLAGS="-mmacosx-version-min=14.0 -isysroot $SDK"
export BISON="$BISON_ROOT/src/bison" BISON_PKGDATADIR="$BISON_ROOT/data"
export FLEX=/Library/Developer/CommandLineTools/usr/bin/flex
export GSTREAMER_CFLAGS="-I$GSTREAMER_SDK/include/gstreamer-1.0 -I$GSTREAMER_SDK/include/glib-2.0 -I$GLIB_CONFIG"
export GSTREAMER_LIBS="-L$GSTREAMER_LIB -lgstvideo-1.0 -lgstaudio-1.0 -lgstbase-1.0 -lgsttag-1.0 -lgstreamer-1.0 -lgobject-2.0 -lglib-2.0"
unset ac_cv_mabi_ms
(cd "$WORK/build" && "$WORK/source/configure" --build=x86_64-apple-darwin --host=x86_64-apple-darwin --enable-win64 --with-mingw=llvm-mingw --disable-tests --without-x --without-freetype --without-gnutls --without-vulkan --with-gstreamer >configure.log 2>&1)
(cd "$WORK/build" && /Library/Developer/CommandLineTools/usr/bin/make -j4 dlls/winegstreamer/x86_64-windows/winegstreamer.dll dlls/winegstreamer/winegstreamer.so >build.log 2>&1)
cp "$WORK/build/dlls/winegstreamer/x86_64-windows/winegstreamer.dll" "$WORK/build/winegstreamer-mf-candidate.dll"
# Only an import interface, no ntdll machine code is copied. Existing runtime
# ntdll must separately export these same names (audited for the frozen pair).
cp "$SCRIPT_DIR/mf-source-ntdll-interface.tbd" "$WORK/build/ntdll-link-interface.tbd"
(cd "$WORK/build" && /Library/Developer/CommandLineTools/usr/bin/clang -arch x86_64 -m64 -dynamiclib -install_name @rpath/winegstreamer.so -Wl,-rpath,@loader_path/ -o winegstreamer-mf-candidate.so dlls/winegstreamer/unixlib.o dlls/winegstreamer/wg_allocator.o dlls/winegstreamer/wg_format.o dlls/winegstreamer/wg_media_type.o dlls/winegstreamer/wg_muxer.o dlls/winegstreamer/wg_parser.o dlls/winegstreamer/wg_transform.o ntdll-link-interface.tbd $GSTREAMER_LIBS -mmacosx-version-min=14.0 -isysroot "$SDK")
/usr/bin/codesign --force --sign - "$WORK/build/winegstreamer-mf-candidate.so"
/usr/bin/codesign --verify --strict "$WORK/build/winegstreamer-mf-candidate.so"
PYTHON=${LW_MF_PYTHON:-/opt/homebrew/bin/python3.13}
"$PYTHON" "$REPO_DIR/tests/wine-mf-fix/generate-atomic-test.py" "$WORK/source/dlls/winegstreamer/wg_parser.c" "$WORK/tests"
cp "$REPO_DIR/tests/wine-mf-fix/test-atomic-read.c" "$REPO_DIR/tests/wine-mf-fix/test-try-read-abi.c" "$WORK/tests/"
/Library/Developer/CommandLineTools/usr/bin/clang -arch x86_64 -isysroot "$SDK" -I"$WORK/build/include" -I"$WORK/source/include" -I"$WORK/source/dlls/winegstreamer" $GSTREAMER_CFLAGS "$WORK/tests/test-atomic-read.c" -L"$GSTREAMER_LIB" -lgstreamer-1.0 -lgobject-2.0 -lglib-2.0 -o "$WORK/tests/test-atomic-read"
DYLD_FALLBACK_LIBRARY_PATH="$GSTREAMER_LIB" GST_PLUGIN_SYSTEM_PATH_1_0= GST_PLUGIN_PATH_1_0= GST_REGISTRY="$WORK/tests/registry.bin" "$WORK/tests/test-atomic-read" > "$WORK/tests/test-atomic-read.json"
for ARCH in x86_64 i686; do
  "$TOOLS/bin/$ARCH-w64-mingw32-clang" -c -I"$WORK/build/include" -I"$WORK/source/include" -I"$WORK/source/dlls/winegstreamer" "$WORK/tests/test-try-read-abi.c" -o "$WORK/tests/abi-$ARCH.o"
done
/usr/bin/shasum -a256 "$WORK/build/winegstreamer-mf-candidate.dll" "$WORK/build/winegstreamer-mf-candidate.so"
echo "Isolated candidate and native-only tests: $WORK"
echo 'No Wine execution or runtime deployment performed. New builds may differ in timestamps/paths/signature bytes.'
