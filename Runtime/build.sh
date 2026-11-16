#!/bin/zsh
# Build Bourbon's Wine runtime from source and install it for Bourbon.
#
# Bourbon publishes no runtime binaries. This downloads, pinned by SHA-256:
#   - CodeWeavers' CrossOver source (LGPL Wine with CodeWeavers' patches); only its wine/ tree is built
#   - Gcenx's WineHQ macOS build, for its x86_64 dylibs (freetype, gnutls, MoltenVK, ...) and Wine Gecko/Mono
#   - DXVK-macOS 1.10.3 and winetricks
# applies patches/, builds Wine on this Mac (arm64 host, x86_64 target, ~5 min) and installs the result into
# Bourbon's Libraries folder (the previous one is kept as "Bourbon-Libraries-previous").
#
# Usage:  Runtime/build.sh [--no-install]
# Needs:  Apple Silicon, Xcode, Rosetta, Homebrew. BOURBON_BUILD_DIR overrides the work dir (~6 GB).
set -euo pipefail

HERE=${0:A:h}
WORK=${BOURBON_BUILD_DIR:-$HOME/Library/Caches/Bourbon/runtime}
APP_SUPPORT="$HOME/Library/Application Support"
LIBRARIES="$APP_SUPPORT/com.isaacmarovitz.Whisky/Libraries"
INSTALL=1; [[ ${1:-} == --no-install ]] && INSTALL=0

CX_VERSION=26.3.0
CX_URL=https://media.codeweavers.com/pub/crossover/source/crossover-sources-$CX_VERSION.tar.gz
CX_SHA256=ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872
DEPS_URL=https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz
DEPS_SHA256=b50dc50ec7f41d58b115a6b685d4d1315ba3c797bd3aa0f49213f2703cb82388
DXVK_URL=https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507/dxvk-macOS-async-v1.10.3-20230507.tar.gz
DXVK_SHA256=f67d99d0a8eeedd7d406b283a3df9f939b5965acb00efcb33d0c6235c195a516
WINETRICKS_URL=https://raw.githubusercontent.com/Winetricks/winetricks/20260125/src/winetricks
WINETRICKS_SHA256=431f82fc74000e6c864409f1d8fb495d696c03928808e3e8acffc45179312a7b

step() { print -P "%F{cyan}==>%f $*"; }
die() { print -P "%F{red}error:%f $*" >&2; exit 1; }

fetch() { # <url> <sha256>: download once into $WORK/downloads, verify, print the path
  local f="$WORK/downloads/${1:t}"
  if [[ ! -f $f ]]; then
    curl -fL --retry 3 -o "$f.part" "$1" >&2 || die "download failed: $1"
    mv "$f.part" "$f"
  fi
  echo "$2  $f" | shasum -a 256 -c --quiet >&2 || { rm -f "$f"; die "checksum mismatch: ${1:t}"; }
  echo "$f"
}

step "Checking prerequisites"
[[ $(uname -m) == arm64 ]] || die "Apple Silicon only"
[[ $WORK != *" "* ]] || die "the build dir can't contain spaces: $WORK (set BOURBON_BUILD_DIR)"
arch -x86_64 /usr/bin/true 2>/dev/null || die "Rosetta missing: softwareupdate --install-rosetta --agree-to-license"
SDK=$(xcrun --show-sdk-path) || die "Xcode missing"
command -v brew >/dev/null || die "Homebrew missing: https://brew.sh"
missing=(); for f in bison mingw-w64 freetype gnutls pkgconf; do brew list --formula $f &>/dev/null || missing+=$f; done
(( ${#missing} )) && { step "brew install ${missing[*]}"; brew install ${missing[@]}; }
BREW=$(brew --prefix)

step "Downloading sources"
mkdir -p "$WORK/downloads"
CX_TGZ=$(fetch $CX_URL $CX_SHA256)
DEPS_TXZ=$(fetch $DEPS_URL $DEPS_SHA256)
DXVK_TGZ=$(fetch $DXVK_URL $DXVK_SHA256)
WINETRICKS=$(fetch $WINETRICKS_URL $WINETRICKS_SHA256)

step "Unpacking and patching"
rm -rf "$WORK"/{src,deps,x86_64-libs,dxvk,build,stage,Libraries}
mkdir -p "$WORK"/{src,deps,x86_64-libs,dxvk,build,stage}
tar -xzf "$CX_TGZ" -C "$WORK/src" sources/wine
tar -xJf "$DEPS_TXZ" -C "$WORK/deps"
tar -xzf "$DXVK_TGZ" -C "$WORK/dxvk"
SRC="$WORK/src/sources/wine"
GW="$WORK/deps/Wine Stable.app/Contents/Resources/wine"
# Wine's makefiles split -L paths on spaces ("Wine Stable.app"), so link from a space-free copy
DEPLIBS="$WORK/x86_64-libs"
cp -a "$GW/lib/"*.dylib "$DEPLIBS/"
for p in "$HERE"/patches/*.patch; do patch -s -d "$SRC" -p1 < "$p"; done

step "Configuring Wine $CX_VERSION (CrossOver source)"
export PATH="$BREW/opt/bison/bin:$BREW/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export SDKROOT=$SDK MACOSX_DEPLOYMENT_TARGET=14.0
export CC="/usr/bin/clang -arch x86_64" CXX="/usr/bin/clang++ -arch x86_64"
PREFIX_MAP="-ffile-prefix-map=$SRC=/wine -ffile-prefix-map=$WORK/build=/wine-build"
export CFLAGS="-O2 $PREFIX_MAP -Wno-error=implicit-function-declaration -Wno-error=incompatible-function-pointer-types -Wno-error=int-conversion"
export CROSSCFLAGS="-O2 $PREFIX_MAP"
export PKG_CONFIG_PATH="$BREW/lib/pkgconfig:$BREW/share/pkgconfig"
# headers from Homebrew, link probes against the x86_64 dylibs that get bundled; Wine dlopen()s these
export FREETYPE_CFLAGS="-I$BREW/include/freetype2" FREETYPE_LIBS="-L$DEPLIBS -lfreetype"
export GNUTLS_CFLAGS="-I$BREW/include" GNUTLS_LIBS="-L$DEPLIBS -lgnutls"
export ac_cv_lib_soname_freetype=libfreetype.6.dylib ac_cv_lib_soname_gnutls=libgnutls.30.dylib
export ac_cv_lib_soname_MoltenVK=libMoltenVK.dylib ac_cv_func_pipe2=no
cd "$WORK/build"
"$SRC/configure" --host=x86_64-apple-darwin --enable-archs=i386,x86_64 --disable-tests \
  --without-x --without-wayland --without-gstreamer --without-ffmpeg --without-oss --without-alsa \
  --without-pulse --without-sane --without-usb --without-v4l2 --without-pcap --without-capi \
  --without-opencl --without-cups --without-dbus --without-sdl --prefix=/opt/bourbon-wine \
  > configure.log 2>&1 || { tail -20 configure.log; die "configure failed ($WORK/build/configure.log)"; }
# tools/sfnt2fon links freetype by its bare name and runs during the build; SIP strips DYLD_* from
# make's children, but dyld also searches the working directory
ln -sf "$DEPLIBS/libfreetype.6.dylib" libfreetype.dylib

step "Building (a few minutes)"
make -j"$(sysctl -n hw.ncpu)" > make.log 2>&1 || { grep -E "error" make.log | tail -20; die "build failed ($WORK/build/make.log)"; }
make -j"$(sysctl -n hw.ncpu)" install-lib DESTDIR="$WORK/stage" > install.log 2>&1 || die "install failed"

step "Assembling the runtime"
L="$WORK/Libraries"
mkdir -p "$L/DXVK/x64" "$L/DXVK/x32"
mv "$WORK/stage/opt/bourbon-wine" "$L/Wine"
cp -a "$DEPLIBS"/*.dylib "$L/Wine/lib/"
mkdir -p "$L/Wine/share/wine"
cp -a "$GW/share/wine/gecko" "$GW/share/wine/mono" "$L/Wine/share/wine/"
for f in "$L"/Wine/lib/wine/x86_64-unix/*.so; do
  otool -l "$f" | grep -q "path @loader_path/../../ " || install_name_tool -add_rpath @loader_path/../../ "$f" 2>/dev/null
done
find "$L/Wine/bin" "$L/Wine/lib" -type f \( -perm -u+x -o -name "*.so" -o -name "*.dylib" \) -print0 |
  while IFS= read -r -d '' f; do file -b "$f" | grep -q Mach-O && codesign -f -s - "$f" 2>/dev/null || true; done
for a in x64 x32; do cp "$WORK"/dxvk/*/$a/{d3d10core,d3d11,dxgi}.dll "$L/DXVK/$a/"; done
install -m 755 "$WINETRICKS" "$L/winetricks"
env -i HOME="$WORK" PATH=/usr/bin:/bin sh "$L/winetricks" list-all 2>/dev/null |
  sed -n '/^=====/,$p' | sed "s#$WORK#~#g" > "$L/verbs.txt"
v=(${(s:.:)CX_VERSION})
cat > "$L/WhiskyWineVersion.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>version</key>
	<dict>
		<key>build</key><string></string>
		<key>major</key><integer>${v[1]}</integer>
		<key>minor</key><integer>${v[2]}</integer>
		<key>patch</key><integer>${v[3]}</integer>
		<key>preRelease</key><string></string>
	</dict>
</dict>
</plist>
EOF
"$L/Wine/bin/wine" --version >/dev/null || die "built wine does not run"

if (( ! INSTALL )); then
  step "Built: $L (not installed)"
  exit 0
fi
step "Installing into $LIBRARIES"
pgrep -q wineserver && die "Wine is running: quit Bourbon and its programs, then rerun"
if [[ -d $LIBRARIES ]]; then
  rm -rf "$APP_SUPPORT/Bourbon-Libraries-previous"
  mv "$LIBRARIES" "$APP_SUPPORT/Bourbon-Libraries-previous"
fi
mkdir -p "${LIBRARIES:h}"
ditto "$L" "$LIBRARIES"
step "Done: Wine $("$LIBRARIES/Wine/bin/wine" --version) (CrossOver $CX_VERSION source)"
