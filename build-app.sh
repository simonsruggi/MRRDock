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
mkdir -p "$APP/Contents/Frameworks"
cp .build/apple/Products/Release/MRRDock "$APP/Contents/MacOS/MRRDock"
cp MRRDock/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework \
      "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/MRRDock" 2>/dev/null || true
sed 's|<key>CFBundleName</key>|<key>CFBundleExecutable</key><string>MRRDock</string><key>CFBundleName</key>|' \
    MRRDock/Info.plist > "$APP/Contents/Info.plist"

# Signed with a Developer ID when one is available, ad-hoc otherwise.
#
# This is not about Gatekeeper: an ad-hoc signature changes with every build, so
# the Keychain stops recognising the app and asks for your password again after
# each rebuild. A stable identity keeps the saved API keys reachable.
IDENTITY="${MRRDOCK_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/{print $2; exit}')}"
if [ -n "$IDENTITY" ]; then
    echo "Signing with: $IDENTITY"
    codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
else
    echo "No Developer ID found, signing ad-hoc (the Keychain will re-prompt after each rebuild)"
    codesign --force --sign - "$APP"
fi
echo "Built $APP"
