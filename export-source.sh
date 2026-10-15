#!/bin/zsh
set -eu
cd "$(dirname "$0")"
MODE="${1:-release}"
if [[ "$MODE" != release && "$MODE" != --preview ]]; then
    printf 'Usage: zsh export-source.sh [--preview]\n' >&2; exit 1
fi
if [ ! -f LICENSE ] && [ "$MODE" != --preview ]; then
    printf 'Project LICENSE and owner attribution are not confirmed. Use --preview for a local draft only.\n' >&2
    exit 1
fi
STAGING=$(mktemp -d /private/tmp/orbit-source.XXXXXX)
PACKAGE="$STAGING/OrbitConvert"
mkdir -p "$PACKAGE"
cp -R Sources Assets "$PACKAGE/"
cp -R Vendor "$PACKAGE/"
cp LAME_LICENSE.txt "$PACKAGE/"
cp FLAC_LICENSE.txt OGG_LICENSE.txt "$PACKAGE/"
cp UNRAR_LICENSE.txt "$PACKAGE/"
for file in Package.swift Info.plist build.sh export-source.sh BUILDING.md GITHUB_PUBLISH.md THIRD_PARTY.md FILEFLIPPER_LICENSE.txt WEBP_LICENSE.txt WEBP_PATENTS.txt .gitignore; do
    cp "$file" "$PACKAGE/$file"
done
cp README-GITHUB.md "$PACKAGE/README.md"
cp README-GITHUB.md "$PACKAGE/README-GITHUB.md"
if [ -f LICENSE ]; then cp LICENSE "$PACKAGE/LICENSE"; fi
mkdir -p dist
NAME=OrbitConvert-source.zip
if [ "$MODE" = --preview ]; then NAME=OrbitConvert-source-preview.zip; fi
ditto --norsrc --noextattr --keepParent -c -k "$PACKAGE" "$PWD/dist/$NAME"
printf 'Source directory: %s\nSource archive: %s\n' "$PACKAGE" "$PWD/dist/$NAME"
