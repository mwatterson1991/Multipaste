#!/bin/bash
# Builds the app into ./build and opens it. Everything it prints is also saved to build.log.
set -uo pipefail
cd "$(dirname "$0")"

NAME="Multipaste"
APP="build/$NAME.app"

build() {
  echo "== $(date) =="
  if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "MISSING_TOOLS: run 'xcode-select --install', wait for it to finish, then run this again."
    return 2
  fi
  sw_vers 2>/dev/null
  xcrun swiftc --version 2>&1 | head -1

  pkill -x "$NAME" 2>/dev/null
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" || return 1
  cp Info.plist "$APP/Contents/Info.plist" || return 1
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns" || return 1

  xcrun swiftc -O -swift-version 5 \
    -target "$(uname -m)-apple-macos13.0" \
    -o "$APP/Contents/MacOS/$NAME" \
    Sources/*.swift || return 1

  codesign --force --sign - "$APP" || return 1
  echo "BUILD_OK"
}

build 2>&1 | tee build.log
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ]; then
  echo "BUILD_FAILED" | tee -a build.log
  exit "$status"
fi
open "$APP"
