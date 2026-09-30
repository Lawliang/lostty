#!/bin/sh
# Builds Lostty (ReleaseLocal) and installs /Applications/Lostty.app.
set -eu
cd "$(dirname "$0")/.."
export PATH="$(brew --prefix zig@0.15)/bin:$PATH"
zig build -Demit-macos-app=false -Doptimize=ReleaseFast
mkdir -p macos/build
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration ReleaseLocal \
  SYMROOT="$PWD/macos/build" build > macos/build/last-install.log 2>&1 || true
grep -q "\*\* BUILD SUCCEEDED \*\*" macos/build/last-install.log || {
  tail -20 macos/build/last-install.log
  echo "Build failed; see macos/build/last-install.log" >&2
  exit 1
}
APP="macos/build/ReleaseLocal/Ghostty.app"
if [ -e "$APP" ] && codesign -dv "$APP" >/dev/null 2>&1; then
  echo "$APP is already signed by the build; not re-signing."
else
  echo "$APP is unsigned or invalid; ad-hoc signing (preserving entitlements/flags)."
  codesign --force --sign - --preserve-metadata=entitlements,flags "$APP"
fi
rm -rf "/Applications/Lostty.app" "/Applications/Ghostty Skins.app"
cp -R "$APP" "/Applications/Lostty.app"
# Stamp the hologram-pink Blueprint icon so Finder/Spotlight show it before
# the first launch (the Dock tile plugin keeps it in sync afterwards).
ICON="$PWD/macos/Assets.xcassets/AppIconImage.imageset/macOS-AppIcon-1024px.png"
swift - "$ICON" <<'SWIFT' || echo "warning: could not set the Finder icon" >&2
import AppKit
let args = CommandLine.arguments
if let image = NSImage(contentsOfFile: args[1]) {
    NSWorkspace.shared.setIcon(image, forFile: "/Applications/Lostty.app")
}
SWIFT
echo "Installed /Applications/Lostty.app"
