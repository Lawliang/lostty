#!/bin/sh
# Builds Lostty (ReleaseLocal) and installs /Applications/Lostty.app.
#   macos/install.sh             Lostty Beta (this Mac runs the beta features)
#   macos/install.sh --stable    stable, what people download
#   macos/install.sh --previous  back to the build this one replaced
set -eu
cd "$(dirname "$0")/.."
# Each install is recorded, for `lostty +peers` and the next install: the
# worktree and commit it was built from, and how many files were
# uncommitted. The build it replaced keeps its record beside it.
RECORD="${XDG_CONFIG_HOME:-$HOME/.config}/lostty/installed-build"

# --previous: back to the build this one replaced, then restart into it
# (or open it, when the current one isn't running).
if [ "${1:-}" = "--previous" ]; then
  PREV="/Applications/Lostty (previous).app"
  [ -d "$PREV" ] || { echo "No previous build to go back to." >&2; exit 1; }
  rm -rf "/Applications/Lostty (swap).app"
  mv /Applications/Lostty.app "/Applications/Lostty (swap).app"
  mv "$PREV" /Applications/Lostty.app
  mv "/Applications/Lostty (swap).app" "$PREV"
  if [ -f "$RECORD.previous" ]; then
    if [ -f "$RECORD" ]; then mv "$RECORD" "$RECORD.swap"; fi
    mv "$RECORD.previous" "$RECORD"
    if [ -f "$RECORD.swap" ]; then mv "$RECORD.swap" "$RECORD.previous"; fi
  fi
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
# The beta by default: this Mac runs the beta features (CONTRIBUTING.md →
# Stable and beta). --stable builds what people download.
CHANNEL=beta
if [ "${1:-}" = "--stable" ]; then CHANNEL=stable; shift; fi
if [ "$CHANNEL" = beta ]; then
  set -- LOSTTY_CHANNEL=beta "INFOPLIST_KEY_CFBundleDisplayName=Lostty Beta" \
    ASSETCATALOG_COMPILER_APPICON_NAME=LosttyMacBetaIcon
else
  set --
fi
# A build made in another worktree can have work this one doesn't: commits
# this branch lacks, or changes never committed. Installing over it drops
# that work from the app, so say so (`lostty +peers` shows who has it).
ROOT=$(git rev-parse --show-toplevel)
UNCOMMITTED=$({ git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u | wc -l | tr -d ' ')
WARNING=""
if [ -f "$RECORD" ]; then
  OLD_TREE=$(sed -n 's/^worktree=//p' "$RECORD")
  OLD_COMMIT=$(sed -n 's/^commit=//p' "$RECORD")
  OLD_UNCOMMITTED=$(sed -n 's/^uncommitted=//p' "$RECORD")
  if [ "$OLD_TREE" != "$ROOT" ]; then
    if [ "${OLD_UNCOMMITTED:-0}" != 0 ] || ! git merge-base --is-ancestor "$OLD_COMMIT" HEAD 2>/dev/null; then
      WARNING="Warning: the build this replaces was made in $(basename "$OLD_TREE") and has work this worktree doesn't (${OLD_UNCOMMITTED:-0} files uncommitted there). Check with its terminal (lostty +peers); install.sh --previous puts it back."
      echo "$WARNING" >&2
    fi
  fi
fi
export PATH="$(brew --prefix zig@0.15)/bin:$PATH"
# The engine takes its version from git and stops on any tag but its own
# vX.Y.Z, such as Lostty's v0.4, v0.4-beta.1 and beta: name it instead.
ENGINE_VERSION="$(sed -n 's/^ *\.version = "\(.*\)",$/\1/p' build.zig.zon)-dev+$(git rev-parse --short HEAD)"
zig build -Demit-macos-app=false -Doptimize=ReleaseFast -Dversion-string="$ENGINE_VERSION"
mkdir -p macos/build
# The commit goes in the app, so the What's New card knows each build.
COMMIT=$(git rev-parse --short HEAD)
# The scheme turns code coverage on for every build. An instrumented Lostty
# drops a default.profraw wherever its Claude hooks run, so switch it off.
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  xcodebuild -project macos/Lostty.xcodeproj -scheme Lostty -configuration ReleaseLocal \
  SYMROOT="$PWD/macos/build" ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO \
  LOSTTY_BUILD_COMMIT="$COMMIT" "$@" build > macos/build/last-install.log 2>&1 || true
grep -q "\*\* BUILD SUCCEEDED \*\*" macos/build/last-install.log || {
  tail -20 macos/build/last-install.log
  echo "Build failed; see macos/build/last-install.log" >&2
  exit 1
}
APP="macos/build/ReleaseLocal/Lostty.app"
WANT=""; [ "$CHANNEL" = beta ] && WANT=beta
[ "$(/usr/libexec/PlistBuddy -c 'Print :LosttyChannel' "$APP/Contents/Info.plist")" = "$WANT" ] || {
  echo "The build isn't the $CHANNEL channel; see macos/build/last-install.log" >&2
  exit 1
}
# What's new since the build this replaces, for the What's New card when
# WhatsNew.md hasn't changed: its commits (none on a first install). Before
# signing: a file added to the app after would break its signature.
PREV=$(/usr/libexec/PlistBuddy -c 'Print :LosttyBuildCommit' /Applications/Lostty.app/Contents/Info.plist 2>/dev/null || true)
rm -f "$APP/Contents/Resources/BuildNotes.md"
if [ -n "$PREV" ] && [ "$PREV" != "$COMMIT" ] && git merge-base --is-ancestor "$PREV" HEAD 2>/dev/null; then
  git log --no-merges --format=%s "$PREV..HEAD" | python3 -I macos/release_helper.py notes \
    > "$APP/Contents/Resources/BuildNotes.md"
fi
if [ -e "$APP" ] && codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
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
mkdir -p "$(dirname "$RECORD")"
if [ -f "$RECORD" ]; then mv "$RECORD" "$RECORD.previous"; fi
cat > "$RECORD" <<RECORD
worktree=$ROOT
branch=$(git branch --show-current)
commit=$(git rev-parse HEAD)
uncommitted=$UNCOMMITTED
channel=$CHANNEL
at=$(date '+%Y-%m-%d %H:%M')
RECORD
if [ "$CHANNEL" = beta ]; then echo "Installed /Applications/Lostty.app (Lostty Beta)"
else echo "Installed /Applications/Lostty.app (stable)"; fi
echo "Switch with Lostty's menu bar → Restart to Update (keeps your terminals)."
echo "Don't Quit Lostty to update: Quit ends every terminal session."
if [ -n "$WARNING" ]; then echo "$WARNING" >&2; fi
