#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE="$ROOT/Resources/AppIcon.png"
OUTPUT="$ROOT/Resources/AppIcon.icns"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/zvec-studio-app-icon.XXXXXX")
ICONSET="$WORK_DIR/AppIcon.iconset"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

test -f "$SOURCE"
WIDTH=$(sips -g pixelWidth "$SOURCE" | awk '/pixelWidth/ { print $2 }')
HEIGHT=$(sips -g pixelHeight "$SOURCE" | awk '/pixelHeight/ { print $2 }')
if [ "$WIDTH" != 1024 ] || [ "$HEIGHT" != 1024 ]; then
    echo 'Resources/AppIcon.png must be exactly 1024x1024 pixels' >&2
    exit 1
fi

mkdir -p "$ICONSET"

sips -z 16 16 "$SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$OUTPUT"
echo "$OUTPUT"
