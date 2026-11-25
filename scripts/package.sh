#!/bin/bash
# Builds the app for both kinds of Mac (Apple silicon and Intel) and zips it, ready to download.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Multipaste"
APP="build/$NAME.app"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/slices
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

for ARCH in arm64 x86_64; do
  xcrun swiftc -O -swift-version 5 \
    -target "$ARCH-apple-macos13.0" \
    -o "build/slices/$NAME-$ARCH" \
    Sources/*.swift
done

lipo -create build/slices/* -output "$APP/Contents/MacOS/$NAME"
codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"

# ditto keeps the app intact inside the zip; a plain zip can break it.
ditto -c -k --keepParent "$APP" "build/$NAME.zip"
echo "PACKAGED build/$NAME.zip"
