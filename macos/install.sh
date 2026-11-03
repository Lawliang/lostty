#!/bin/sh
# Builds Lostty (ReleaseLocal) and installs /Applications/Lostty.app.
#   macos/install.sh             Lostty Beta (this Mac runs the beta features)
#   macos/install.sh --stable    stable, what people download
#   macos/install.sh --previous  back to the build this one replaced
#   macos/install.sh --edition orca  an edition of Lostty Beta (AGENTS.md → Editions);
#                                    on an edition/<name> branch the name is implied
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
EDITION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --stable) CHANNEL=stable; shift ;;
    --edition) [ $# -ge 2 ] || { echo "--edition needs a name, such as --edition orca." >&2; exit 1; }
      EDITION=$2; shift 2 ;;
    *) echo "Unknown option $1." >&2; exit 1 ;;
  esac
done
# Which edition this is (AGENTS.md → Editions): Core, or Core with one
# harness on an edition/<name> branch. A branch built on an edition is that
# edition, so a worktree branched from edition/orca can't install as Core.
BRANCH=$(git branch --show-current)
case "$BRANCH" in edition/*) [ -n "$EDITION" ] || EDITION=${BRANCH#edition/} ;; esac
[ -n "$EDITION" ] || EDITION=core
case "$EDITION" in *[!a-z0-9-]* | -*)
  echo "An edition's name is lowercase letters, digits and dashes, like its branch: edition/$EDITION." >&2; exit 1 ;;
esac
for REF in $(git for-each-ref --format='%(refname:short)' refs/heads/edition/); do
  NAME=${REF#edition/}
  [ "$NAME" = "$EDITION" ] && continue
  if git merge-base --is-ancestor "$REF" HEAD && ! git merge-base --is-ancestor "$REF" main; then
    echo "This branch has $REF's work, so it's the $NAME edition: run install.sh --edition $NAME." >&2; exit 1
  fi
done
if [ "$EDITION" != core ]; then
  [ "$CHANNEL" = beta ] || { echo "Editions are Lostty Beta only; drop --stable." >&2; exit 1; }
  git rev-parse -q --verify "refs/heads/edition/$EDITION" >/dev/null && git merge-base --is-ancestor "edition/$EDITION" HEAD \
    || { echo "There's no edition/$EDITION branch under this one. Start an edition from main: git branch edition/$EDITION main" >&2; exit 1; }
fi
if [ "$CHANNEL" = beta ]; then
  set -- LOSTTY_CHANNEL=beta LOSTTY_EDITION="$EDITION" "INFOPLIST_KEY_CFBundleDisplayName=Lostty Beta" \
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
if [ "$CHANNEL" = beta ]; then
  [ "$(/usr/libexec/PlistBuddy -c 'Print :LosttyEdition' "$APP/Contents/Info.plist")" = "$EDITION" ] || {
    echo "The build isn't the $EDITION edition; see macos/build/last-install.log" >&2
    exit 1
  }
fi
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
# Every beta edition installed here is kept in the library, so the menu
# bar's Edition submenu can switch back without a build. The build being
# replaced goes in first when the library has no copy of its edition: the
# Core installed before editions existed is how the library starts.
LIBRARY="$HOME/Library/Application Support/Lostty/Editions"
mkdir -p "$LIBRARY"
keep_edition() { # app name
  rm -rf "$LIBRARY/$2 (copying).app"
  cp -R "$1" "$LIBRARY/$2 (copying).app"
  rm -rf "$LIBRARY/$2.app"
  mv "$LIBRARY/$2 (copying).app" "$LIBRARY/$2.app"
}
OLD_INFO=/Applications/Lostty.app/Contents/Info.plist
if [ -f "$OLD_INFO" ] && [ "$(/usr/libexec/PlistBuddy -c 'Print :LosttyChannel' "$OLD_INFO" 2>/dev/null)" = beta ]; then
  OLD_EDITION=$(/usr/libexec/PlistBuddy -c 'Print :LosttyEdition' "$OLD_INFO" 2>/dev/null || true)
  case "$OLD_EDITION" in "" | *[!a-z0-9-]* | -*) OLD_EDITION=core ;; esac
  [ -d "$LIBRARY/$OLD_EDITION.app" ] || keep_edition /Applications/Lostty.app "$OLD_EDITION"
fi
[ "$CHANNEL" = beta ] && keep_edition "$APP" "$EDITION"
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
edition=$EDITION
at=$(date '+%Y-%m-%d %H:%M')
RECORD
if [ "$CHANNEL" = stable ]; then echo "Installed /Applications/Lostty.app (stable)"
elif [ "$EDITION" = core ]; then echo "Installed /Applications/Lostty.app (Lostty Beta)"
else echo "Installed /Applications/Lostty.app (Lostty Beta, $EDITION edition). Back to Core: menu bar → Edition → Core."; fi
echo "Switch with Lostty's menu bar → Restart to Update (keeps your terminals)."
echo "Don't Quit Lostty to update: Quit ends every terminal session."
if [ -n "$WARNING" ]; then echo "$WARNING" >&2; fi
