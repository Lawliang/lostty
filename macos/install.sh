#!/bin/sh
# Builds Lostty (ReleaseLocal) and installs /Applications/Lostty.app.
set -eu
cd "$(dirname "$0")/.."

# --previous: back to the build this one replaced, then restart into it
# (or open it, when the current one isn't running).
if [ "${1:-}" = "--previous" ]; then
  PREV="/Applications/Lostty (previous).app"
  [ -d "$PREV" ] || { echo "No previous build to go back to." >&2; exit 1; }
  rm -rf "/Applications/Lostty (swap).app"
  mv /Applications/Lostty.app "/Applications/Lostty (swap).app"
  mv "$PREV" /Applications/Lostty.app
  mv "/Applications/Lostty (swap).app" "$PREV"
  if pgrep -xf /Applications/Lostty.app/Contents/MacOS/lostty >/dev/null; then
    # The raw event: compiling "restart to update" needs a dictionary that
    # has it, and the running Lostty may be older.
    osascript -e 'tell application id "com.lawliang.lostty" to «event GhstRsUp»' \
      || echo "Swapped. Choose Restart to Update in Lostty's menu bar."
  else
    open /Applications/Lostty.app
  fi
  echo "Back on the previous build."
  exit 0
fi
export PATH="$(brew --prefix zig@0.15)/bin:$PATH"
zig build -Demit-macos-app=false -Doptimize=ReleaseFast
mkdir -p macos/build
# The scheme turns code coverage on for every build. An instrumented Lostty
# drops a default.profraw wherever its Claude hooks run, so switch it off.
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  xcodebuild -project macos/Lostty.xcodeproj -scheme Lostty -configuration ReleaseLocal \
  SYMROOT="$PWD/macos/build" ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO \
  build > macos/build/last-install.log 2>&1 || true
grep -q "\*\* BUILD SUCCEEDED \*\*" macos/build/last-install.log || {
  tail -20 macos/build/last-install.log
  echo "Build failed; see macos/build/last-install.log" >&2
  exit 1
}
APP="macos/build/ReleaseLocal/Lostty.app"
if [ -e "$APP" ] && codesign -dv "$APP" >/dev/null 2>&1; then
  echo "$APP is already signed by the build; not re-signing."
else
  echo "$APP is unsigned or invalid; ad-hoc signing (preserving entitlements/flags)."
  codesign --force --sign - --preserve-metadata=entitlements,flags "$APP"
fi
# A signature that stays the same from build to build: Location (the
# hotspot switch) and Lostty's keychain items follow it, and an ad-hoc one
# changes every build, so each update would lose them.
IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)
if [ -n "$IDENTITY" ]; then
  echo "Signing as $IDENTITY."
  codesign --force --deep --timestamp=none --sign "$IDENTITY" --preserve-metadata=entitlements,flags "$APP"
  codesign --verify --deep --strict "$APP"
fi
# Keep the build being replaced: the menu bar's Go Back to Previous Build,
# or `install.sh --previous` when the new one won't start.
rm -rf "/Applications/Lostty (previous).app" "/Applications/Ghostty Skins.app"
# Copied aside, then renamed into place in one step: a Lostty checking for
# a new build never sees half of one.
rm -rf "/Applications/Lostty (installing).app"
cp -R "$APP" "/Applications/Lostty (installing).app"
if [ -d /Applications/Lostty.app ]; then
  mv /Applications/Lostty.app "/Applications/Lostty (previous).app"
fi
mv "/Applications/Lostty (installing).app" /Applications/Lostty.app
# The Dock caches icons by path, so a new icon at the same path stays stale
# until LaunchServices re-reads the bundle.
touch /Applications/Lostty.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Lostty.app
echo "Installed /Applications/Lostty.app"
echo "Switch with Lostty's menu bar → Restart to Update (keeps your terminals)."
echo "Don't Quit Lostty to update: Quit ends every terminal session."
