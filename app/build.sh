#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Siber Neo"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
DMG="$BUILD_DIR/Siber-Neo-$VERSION.dmg"
MODE="${1:-}"

echo "→ Compile (release)..."
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/SiberNeo"

echo "→ Assembling app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/SiberNeo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/en.lproj Resources/id.lproj "$APP/Contents/Resources/"

if [ -f Resources/AppIcon.png ]; then
    echo "→ Generating app icon..."
    ICONSET="$BUILD_DIR/AppIcon.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    for SIZE in 16 32 128 256 512; do
        sips -z $SIZE $SIZE Resources/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" > /dev/null
        DOUBLE=$((SIZE * 2))
        sips -z $DOUBLE $DOUBLE Resources/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" > /dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
fi

if [ -n "${DEVELOPER_ID:-}" ]; then
    echo "→ Code signing with Developer ID..."
    codesign --force --deep --timestamp --options runtime \
        --entitlements Resources/SiberNeo.entitlements \
        --sign "$DEVELOPER_ID" "$APP"
else
    echo "→ Code signing (ad-hoc, local use)..."
    codesign --force --deep --sign - "$APP"
fi

if [ "$MODE" = "--dmg" ]; then
    echo "→ Creating DMG installer..."
    STAGE="$BUILD_DIR/dmg-stage"
    rm -rf "$STAGE" "$DMG"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" > /dev/null
    rm -rf "$STAGE"

    if [ -n "${DEVELOPER_ID:-}" ]; then
        codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
    fi
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        echo "→ Apple notarization (this takes a few minutes)..."
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
    fi
    echo "✓ Installer ready: $DMG"
    exit 0
fi

if [ "$MODE" = "--install" ]; then
    echo "→ Installing to /Applications..."
    pkill -x SiberNeo 2>/dev/null || true
    pkill -x SiberNotch 2>/dev/null || true
    rm -rf "/Applications/Siber Notch.app"
    rm -rf "/Applications/$APP_NAME.app"
    sleep 1
    cp -R "$APP" /Applications/
    sleep 1
    open "/Applications/$APP_NAME.app" 2>/dev/null || { sleep 2; open "/Applications/$APP_NAME.app"; }
    echo "✓ Installed at /Applications/$APP_NAME.app"
else
    echo "✓ Done: $APP"
    echo "  Run: open \"$APP\""
fi
