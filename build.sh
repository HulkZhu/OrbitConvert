#!/bin/zsh
set -eu
cd "$(dirname "$0")"
mkdir -p .build/ModuleCache
mkdir -p .build/UnRAR
cp -R Vendor/UnRAR/unrar/. .build/UnRAR/
make -C .build/UnRAR -j4 lib CXXFLAGS='-O2 -std=c++11 -fPIC -mmacosx-version-min=13.0' > .build/unrar-build.log 2>&1
clang++ -dynamiclib -std=c++11 -D_UNIX -mmacosx-version-min=13.0 -install_name @rpath/libOrbitUnRAR.dylib Vendor/UnRAR/OrbitUnRAR.cpp .build/UnRAR/libunrar.a -o .build/libOrbitUnRAR.dylib
WEBP_LIB="${ORBIT_WEBP_LIB:-}"
LAME_LIB="${ORBIT_LAME_LIB:-/private/tmp/lame-3.100/libmp3lame/.libs}"
test -s "$LAME_LIB/libmp3lame.0.dylib"
if [ -z "$WEBP_LIB" ]; then
    if command -v brew >/dev/null 2>&1; then
        WEBP_LIB="$(brew --prefix webp 2>/dev/null)/lib"
    fi
fi
if [ ! -f "$WEBP_LIB/libwebp.7.dylib" ] || [ ! -f "$WEBP_LIB/libsharpyuv.0.dylib" ]; then
    printf 'Set ORBIT_WEBP_LIB to your libwebp 1.6.0 shared-library directory (see BUILDING.md).\n' >&2
    exit 1
fi
for license in LICENSE THIRD_PARTY.md FILEFLIPPER_LICENSE.txt WEBP_LICENSE.txt WEBP_PATENTS.txt; do
    test -s "$license" || { printf 'Missing license: %s\n' "$license" >&2; exit 1; }
done
test -s Assets/AppIcon.png
xcrun swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$PWD/.build/ModuleCache" Sources/OrbitConvert/*.swift -o .build/OrbitConvert
STAGING=$(mktemp -d /private/tmp/orbit-build.XXXXXX)
APP="$STAGING/OrbitConvert.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/OrbitConvert "$APP/Contents/MacOS/OrbitConvert"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp THIRD_PARTY.md "$APP/Contents/Resources/THIRD_PARTY.md"
cp FILEFLIPPER_LICENSE.txt "$APP/Contents/Resources/FILEFLIPPER_LICENSE.txt"
cp WEBP_PATENTS.txt "$APP/Contents/Resources/WEBP_PATENTS.txt"
cp LAME_LICENSE.txt "$APP/Contents/Resources/LAME_LICENSE.txt"
cp UNRAR_LICENSE.txt "$APP/Contents/Resources/UNRAR_LICENSE.txt"
cp .build/libOrbitUnRAR.dylib "$APP/Contents/Frameworks/libOrbitUnRAR.dylib"
cp FLAC_LICENSE.txt OGG_LICENSE.txt "$APP/Contents/Resources/"
cp -L /opt/homebrew/lib/libFLAC.14.dylib /opt/homebrew/lib/libogg.0.dylib "$APP/Contents/Frameworks/"
install_name_tool -change /opt/homebrew/opt/libogg/lib/libogg.0.dylib @loader_path/libogg.0.dylib "$APP/Contents/Frameworks/libFLAC.14.dylib"
cp -R Vendor/LAME "$APP/Contents/Resources/LAME-Source"
cp -L "$LAME_LIB/libmp3lame.0.dylib" "$APP/Contents/Frameworks/libmp3lame.0.dylib"
install_name_tool -id @rpath/libmp3lame.0.dylib "$APP/Contents/Frameworks/libmp3lame.0.dylib"
if [ -f LICENSE ]; then cp LICENSE "$APP/Contents/Resources/LICENSE"; fi
cp -L "$WEBP_LIB/libwebp.7.dylib" "$APP/Contents/Frameworks/libwebp.7.dylib"
cp -L "$WEBP_LIB/libsharpyuv.0.dylib" "$APP/Contents/Frameworks/libsharpyuv.0.dylib"
# Rewrite only SharpYUV. Reject any other unbundled non-system dependency.
for dependency in ${(f)"$(otool -L "$APP/Contents/Frameworks/libwebp.7.dylib" | tail -n +3 | awk '{print $1}')"}; do
    if [[ "$dependency" == *libsharpyuv*.dylib ]]; then
        install_name_tool -change "$dependency" @loader_path/libsharpyuv.0.dylib "$APP/Contents/Frameworks/libwebp.7.dylib"
    elif [[ "$dependency" != /usr/lib/* && "$dependency" != /System/Library/* ]]; then
        printf 'Unbundled WebP dependency: %s\n' "$dependency" >&2; exit 1
    fi
done
for dependency in ${(f)"$(otool -L "$APP/Contents/Frameworks/libsharpyuv.0.dylib" | tail -n +3 | awk '{print $1}')"}; do
    if [[ "$dependency" != /usr/lib/* && "$dependency" != /System/Library/* ]]; then
        printf 'Unbundled SharpYUV dependency: %s\n' "$dependency" >&2; exit 1
    fi
done
cp WEBP_LICENSE.txt "$APP/Contents/Resources/WEBP_LICENSE.txt"
mkdir -p .build/AppIcon.iconset
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/AppIcon.png --out ".build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Assets/AppIcon.png --out ".build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
xcrun swiftc -module-cache-path "$PWD/.build/ModuleCache" Assets/PackIcon.swift -o .build/PackIcon
.build/PackIcon .build/AppIcon.iconset "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP/Contents/Frameworks/libsharpyuv.0.dylib"
codesign --force --sign - "$APP/Contents/Frameworks/libwebp.7.dylib"
codesign --force --sign - "$APP/Contents/Frameworks/libmp3lame.0.dylib"
codesign --force --sign - "$APP/Contents/Frameworks/libFLAC.14.dylib"
codesign --force --sign - "$APP/Contents/Frameworks/libogg.0.dylib"
codesign --force --sign - "$APP/Contents/Frameworks/libOrbitUnRAR.dylib"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
APP_KB=$(du -sk "$APP" | awk '{print $1}')
if [ "$APP_KB" -gt 48828 ]; then
    printf 'App exceeds the 50 MB size limit.\n' >&2
    exit 1
fi
printf 'App installed size: %s KB\n' "$APP_KB"
mkdir -p dist
ditto --norsrc --noextattr --keepParent -c -k "$APP" "$PWD/dist/OrbitConvert-v1.0.2.zip"
printf 'Verified app: %s\n' "$APP"
printf 'Verified app archive: %s\n' "$PWD/dist/OrbitConvert-v1.0.2.zip"
