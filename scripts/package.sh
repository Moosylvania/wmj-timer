#!/bin/bash
# Build a universal release binary, assemble the .app bundle, sign it, and zip
# it for a GitHub Release. Signs with the Developer ID certificate when one is
# in the Keychain (ad-hoc fallback for machines without it); NOTARIZE=1 also
# notarizes with Apple and staples the ticket, using the App Store Connect API
# key configured in .env. Usage: [NOTARIZE=1] bash scripts/package.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:-0.1.0}
APP="dist/WmjQuickTimer.app"
ZIP="dist/Wmj-Quick-Timer-$VERSION.zip"

swift build -c release --arch arm64 --arch x86_64

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/apple/Products/Release/WmjQuickTimer "$APP/Contents/MacOS/WmjQuickTimer"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/Resources/* "$APP/Contents/Resources/"   # app icon + menu bar icon
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"

# Hardened runtime + secure timestamp are required for notarization. No --deep:
# the bundle is a single binary with no nested code.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
if [ -n "$IDENTITY" ]; then
    codesign --force --timestamp --options runtime -s "$IDENTITY" "$APP"
else
    echo "WARNING: no Developer ID certificate found — ad-hoc signing (local testing only)." >&2
    codesign --force -s - "$APP"
fi

ditto -c -k --keepParent "$APP" "$ZIP"

if [ "${NOTARIZE:-0}" = 1 ]; then
    [ -n "$IDENTITY" ] || { echo "NOTARIZE=1 needs a Developer ID certificate in the Keychain."; exit 1; }
    source .env   # APPSTORECONNECT_APIKEY (path to .p8) + APPSTORECONNECT_ISSUERID
    KEY_ID=$(basename "$APPSTORECONNECT_APIKEY" .p8); KEY_ID=${KEY_ID#AuthKey_}
    echo "Submitting to Apple notary service (usually takes a few minutes)…"
    # notarytool can exit 0 on an Invalid verdict, so check the status text.
    OUT=$(xcrun notarytool submit "$ZIP" --key "$APPSTORECONNECT_APIKEY" \
        --key-id "$KEY_ID" --issuer "$APPSTORECONNECT_ISSUERID" --wait) || true
    echo "$OUT"
    echo "$OUT" | grep -q "status: Accepted" || {
        echo "Notarization not accepted. Inspect with:" >&2
        echo "  xcrun notarytool log <submission-id> --key \"$APPSTORECONNECT_APIKEY\" --key-id $KEY_ID --issuer \"$APPSTORECONNECT_ISSUERID\"" >&2
        exit 1
    }
    xcrun stapler staple "$APP"
    ditto -c -k --keepParent "$APP" "$ZIP"   # re-zip: stapling modified the bundle
fi

echo "Built $ZIP"
