#!/usr/bin/env bash
# Builds MRRDock.app (universal) into ./build. No signing identity needed:
# the bundle is ad-hoc signed so it runs locally and on any Mac after the
# usual right-click → Open.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/MRRDock.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' MRRDock/Info.plist)"

echo "Building MRRDock ${VERSION}"
swift build -c release --arch arm64 --arch x86_64

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/apple/Products/Release/MRRDock "$APP/Contents/MacOS/MRRDock"
cp MRRDock/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed 's|<key>CFBundleName</key>|<key>CFBundleExecutable</key><string>MRRDock</string><key>CFBundleName</key>|' \
    MRRDock/Info.plist > "$APP/Contents/Info.plist"

codesign --force --deep --sign - "$APP"
echo "Built $APP"
