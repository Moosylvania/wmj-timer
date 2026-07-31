#!/bin/bash
# Build a universal release binary, assemble the .app bundle, and zip it for
# a GitHub Release. Usage: bash scripts/package.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:-0.1.0}
APP="dist/WmjQuickTimer.app"

swift build -c release --arch arm64 --arch x86_64

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/apple/Products/Release/WmjQuickTimer "$APP/Contents/MacOS/WmjQuickTimer"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/Resources/* "$APP/Contents/Resources/"   # app icon + menu bar icon
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"

codesign --force --deep -s - "$APP"   # ad-hoc signature (unsigned distribution)

ditto -c -k --keepParent "$APP" "dist/Wmj-Quick-Timer-$VERSION.zip"
echo "Built dist/Wmj-Quick-Timer-$VERSION.zip"
