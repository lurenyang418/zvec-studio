#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/dist/Zvec Studio.app"
VERSION=${VERSION:-$(plutil -extract CFBundleShortVersionString raw "$ROOT/Resources/Info.plist")}
export VERSION
DMG="$ROOT/dist/ZvecStudio-$VERSION-arm64.dmg"
DMG_STAGING="$ROOT/dist/dmg-root"

cleanup() {
    rm -rf "$DMG_STAGING"
}
trap cleanup EXIT HUP INT TERM

"$ROOT/scripts/build-app.sh"

codesign --force --sign - "$APP/Contents/Frameworks/CZvec.framework"
codesign --force --sign - "$APP/Contents/MacOS/ZvecStudio"
codesign --force --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "Zvec Studio" -srcfolder "$DMG_STAGING" -format UDZO -ov "$DMG"

echo "$DMG"
