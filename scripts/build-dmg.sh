#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/dist/Zvec Studio.app"
VERSION=${VERSION:-$(plutil -extract CFBundleShortVersionString raw "$ROOT/Resources/Info.plist")}
export VERSION
DMG="$ROOT/dist/ZvecStudio-$VERSION-arm64.dmg"
IDENTITY=${DEVELOPER_ID_APPLICATION:--}

"$ROOT/scripts/build-app.sh"

sign() {
    if [ "$IDENTITY" = "-" ]; then
        codesign --force --sign - "$1"
    else
        codesign --force --timestamp --options runtime --sign "$IDENTITY" "$1"
    fi
}

sign "$APP/Contents/Frameworks/CZvec.framework"
sign "$APP/Contents/MacOS/ZvecStudio"
sign "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

rm -f "$DMG"
hdiutil create -volname "Zvec Studio" -srcfolder "$APP" -format UDZO -ov "$DMG"

if [ "$IDENTITY" != "-" ]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi

if [ -n "${NOTARY_KEY_PATH:-}" ]; then
    [ "$IDENTITY" != "-" ] || { echo 'Notarization requires DEVELOPER_ID_APPLICATION' >&2; exit 1; }
    [ -f "$NOTARY_KEY_PATH" ] || { echo 'NOTARY_KEY_PATH does not exist' >&2; exit 1; }
    [ -n "${NOTARY_KEY_ID:-}" ] || { echo 'NOTARY_KEY_ID is required' >&2; exit 1; }
    [ -n "${NOTARY_ISSUER_ID:-}" ] || { echo 'NOTARY_ISSUER_ID is required' >&2; exit 1; }
    xcrun notarytool submit "$DMG" \
        --key "$NOTARY_KEY_PATH" \
        --key-id "$NOTARY_KEY_ID" \
        --issuer "$NOTARY_ISSUER_ID" \
        --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
elif [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
    [ "$IDENTITY" != "-" ] || { echo 'Notarization requires DEVELOPER_ID_APPLICATION' >&2; exit 1; }
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

if [ "$IDENTITY" != "-" ]; then
    spctl --assess --type execute --verbose=2 "$APP"
fi

echo "$DMG"
