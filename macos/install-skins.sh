#!/bin/sh
# Builds Ghostty Skins (ReleaseLocal) and installs /Applications/Ghostty Skins.app.
set -eu
cd "$(dirname "$0")/.."
export PATH="$(brew --prefix zig@0.15)/bin:$PATH"
zig build -Demit-macos-app=false -Doptimize=ReleaseFast
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration ReleaseLocal \
  SYMROOT="$PWD/macos/build" build | tail -3
APP="macos/build/ReleaseLocal/Ghostty.app"
codesign --force --deep --sign - "$APP"
rm -rf "/Applications/Ghostty Skins.app"
cp -R "$APP" "/Applications/Ghostty Skins.app"
echo "Installed /Applications/Ghostty Skins.app"
