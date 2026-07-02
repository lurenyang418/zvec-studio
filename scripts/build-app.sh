#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/dist/Zvec Studio.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
FRAMEWORKS="$CONTENTS/Frameworks"
RESOURCES="$CONTENTS/Resources"
ZVEC_LICENSE="$ROOT/.build/checkouts/zvec-swift/LICENSE"
ZVEC_NOTICE="$ROOT/.build/checkouts/zvec-swift/NOTICE"
VERSION=${VERSION:-$(plutil -extract CFBundleShortVersionString raw "$ROOT/Resources/Info.plist")}
BUILD_NUMBER=${BUILD_NUMBER:-1}

printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+(\.[0-9]+){2}$' || {
    echo "VERSION must use the form 1.2.3: $VERSION" >&2
    exit 1
}
printf '%s\n' "$BUILD_NUMBER" | grep -Eq '^[1-9][0-9]*$' || {
    echo "BUILD_NUMBER must be a positive integer: $BUILD_NUMBER" >&2
    exit 1
}

cd "$ROOT"
swift build -c release --product ZvecStudio
BIN_DIR=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$MACOS" "$FRAMEWORKS" "$RESOURCES"
cp "$BIN_DIR/ZvecStudio" "$MACOS/ZvecStudio"
cp -R "$BIN_DIR/CZvec.framework" "$FRAMEWORKS/CZvec.framework"
cp -R "$BIN_DIR/zvec-swift_Zvec.bundle" "$RESOURCES/zvec-swift_Zvec.bundle"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"
test -f "$ROOT/LICENSE"
test -f "$ROOT/THIRD_PARTY_NOTICES.md"
test -f "$ZVEC_LICENSE"
test -f "$ZVEC_NOTICE"
cp "$ROOT/LICENSE" "$RESOURCES/LICENSE-ZvecStudio.txt"
cp "$ZVEC_LICENSE" "$RESOURCES/LICENSE-zvec-swift.txt"
cp "$ZVEC_NOTICE" "$RESOURCES/NOTICE-zvec-swift.txt"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$RESOURCES/THIRD_PARTY_NOTICES.md"
cp "$ROOT/README.md" "$RESOURCES/README.md"

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
    /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$CONTENTS/Info.plist"
fi

install_name_tool -add_rpath '@executable_path/../Frameworks' "$MACOS/ZvecStudio"
chmod +x "$MACOS/ZvecStudio"

test -x "$MACOS/ZvecStudio"
test -f "$FRAMEWORKS/CZvec.framework/CZvec"
test -d "$RESOURCES/zvec-swift_Zvec.bundle"
plutil -lint "$CONTENTS/Info.plist"
file "$MACOS/ZvecStudio" | grep -q 'arm64'
otool -L "$MACOS/ZvecStudio" | grep -q '@rpath/CZvec.framework/CZvec'
otool -l "$MACOS/ZvecStudio" | grep -q '@executable_path/../Frameworks'
if otool -L "$MACOS/ZvecStudio" | awk 'NR > 1' | grep -q '/Users/'; then
    echo 'Executable contains a development-machine absolute dependency' >&2
    exit 1
fi

echo "$APP"
