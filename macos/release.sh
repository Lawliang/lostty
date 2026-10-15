#!/bin/sh
# Publishes a Lostty for Mac release: builds it, signs it as Developer ID,
# makes Lostty.dmg, has Apple notarize it, writes Sparkle's appcast.xml, then
# tags vX.Y and creates the GitHub release with both. Run it only when the
# owner says "release". One-time setup: CONTRIBUTING.md → Release.
#   macos/release.sh [--version X.Y] [--dry-run]   --dry-run: everything but publishing
#   macos/release.sh --make-key                     the update-signing key, into the app
set -eu
cd "$(dirname "$0")/.."
export PATH="$(brew --prefix zig@0.15)/bin:$PATH"

TEAM=K85Z63QH48
REPO=Lawliang/lostty
FEED="https://github.com/$REPO/releases/latest/download/appcast.xml"
PROFILE=lostty-notary
PLIST=macos/Lostty-Info.plist
OUT="$PWD/macos/build/release"
DERIVED="$OUT/DerivedData"
SPARKLE_BIN="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin"
HELPER="python3 -I macos/release_helper.py"

OVERRIDE=""; DRY_RUN=0; MAKE_KEY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version) OVERRIDE=${2:?"--version needs X.Y"}; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --make-key) MAKE_KEY=1; shift ;;
    *) echo "Usage: macos/release.sh [--version X.Y] [--dry-run] | --make-key" >&2; exit 2 ;;
  esac
done
mkdir -p "$OUT"

fail() { echo "release: $*" >&2; exit 1; }
step() { echo "==> $*"; }
# The last lines of a failed step's log, then why.
failed() { tail -20 "$1" >&2; fail "$2; see $1"; }

sparkle_tools() {
  [ -x "$SPARKLE_BIN/sign_update" ] && return 0
  step "Fetching Sparkle's tools"
  xcodebuild -resolvePackageDependencies -project macos/Lostty.xcodeproj -scheme Lostty \
    -derivedDataPath "$DERIVED" > "$OUT/resolve.log" 2>&1 || failed "$OUT/resolve.log" "couldn't fetch Sparkle"
  [ -x "$SPARKLE_BIN/sign_update" ] || fail "Sparkle's tools aren't in $SPARKLE_BIN"
}
plist_key() { sed -n '/<key>SUPublicEDKey<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$PLIST"; }

if [ "$MAKE_KEY" = 1 ]; then
  sparkle_tools
  # Makes the key in the login keychain, or keeps the one already there.
  "$SPARKLE_BIN/generate_keys" > "$OUT/keys.log" 2>&1 || failed "$OUT/keys.log" "generate_keys failed"
  KEY=$("$SPARKLE_BIN/generate_keys" -p)
  if [ "$KEY" = "$(plist_key)" ]; then echo "The app already has this Mac's update-signing key."; exit 0; fi
  sed -i '' "/<key>SUPublicEDKey<\/key>/{n;s|<string>.*</string>|<string>$KEY</string>|;}" "$PLIST"
  echo "Put the update-signing key $KEY in $PLIST. Commit it and push it to main before releasing."
  exit 0
fi

step "Checking"
[ -z "$(git status --porcelain)" ] || fail "commit or stash your changes first."
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
  || fail "this commit isn't GitHub's main. Push it to main (or check out origin/main) first."
gh auth status > /dev/null 2>&1 || fail "sign in to GitHub first: gh auth login"
IDENTITY=$(security find-identity -v -p codesigning \
  | sed -n "s/.*\"\(Developer ID Application: .*($TEAM)\)\".*/\1/p" | head -1)
[ -n "$IDENTITY" ] || fail "no Developer ID Application certificate for team $TEAM. In Xcode: Settings → Accounts → Manage Certificates → + → Developer ID Application (the Account Holder makes it)."
xcrun notarytool history --keychain-profile "$PROFILE" > /dev/null 2>&1 \
  || fail "no notarization login. Make an app-specific password at account.apple.com, then run: xcrun notarytool store-credentials $PROFILE --apple-id <your Apple ID> --team-id $TEAM"
sparkle_tools
KEY=$("$SPARKLE_BIN/generate_keys" -p 2> /dev/null || true)
[ -n "$KEY" ] || fail "no update-signing key on this Mac. Run: macos/release.sh --make-key"
[ "$KEY" = "$(plist_key)" ] || fail "the app's SUPublicEDKey isn't this Mac's update-signing key. Run macos/release.sh --make-key, then commit and push."

LATEST=$(gh release list --repo "$REPO" --limit 1 --exclude-drafts --json tagName --jq '.[0].tagName // ""')
VERSION=$($HELPER next-version --latest "$LATEST" --override "$OVERRIDE") || exit 1
TAG="v$VERSION"
BUILD=$(date +%Y%m%d%H%M)
! git rev-parse -q --verify "refs/tags/$TAG" > /dev/null || fail "the tag $TAG already exists on this Mac."

step "Notes for Lostty $VERSION"
NOTES="$OUT/notes.md"
RANGE="-30 HEAD"
if [ -n "$LATEST" ]; then
  git fetch -q origin "refs/tags/$LATEST:refs/tags/$LATEST" 2> /dev/null || true
  git rev-parse -q --verify "refs/tags/$LATEST" > /dev/null && RANGE="$LATEST..HEAD"
fi
# shellcheck disable=SC2086 # RANGE is one or two words on purpose
git log --no-merges --format=%s $RANGE | $HELPER notes > "$NOTES"
${EDITOR:-nano} "$NOTES"
grep -q '[^[:space:]]' "$NOTES" || fail "the notes are empty; nothing was released."

step "Building Lostty $VERSION ($BUILD)"
zig build -Demit-macos-app=false -Doptimize=ReleaseFast > "$OUT/zig.log" 2>&1 \
  || failed "$OUT/zig.log" "the engine build failed"
rm -rf "$OUT/Lostty.xcarchive" "$OUT/export"
xcodebuild archive -project macos/Lostty.xcodeproj -scheme Lostty -configuration Release \
  -destination generic/platform=macOS -archivePath "$OUT/Lostty.xcarchive" -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=$TEAM CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" LOSTTY_UPDATE_FEED="$FEED" \
  ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO \
  > "$OUT/archive.log" 2>&1 || failed "$OUT/archive.log" "the archive failed"
cat > "$OUT/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
EOF
xcodebuild -exportArchive -archivePath "$OUT/Lostty.xcarchive" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates \
  > "$OUT/export.log" 2>&1 || failed "$OUT/export.log" "signing it as Developer ID failed"
APP="$OUT/export/Lostty.app"
codesign --verify --deep --strict "$APP" 2> "$OUT/codesign.log" || failed "$OUT/codesign.log" "the signature doesn't verify"
[ "$(/usr/libexec/PlistBuddy -c 'Print :LosttyUpdateFeed' "$APP/Contents/Info.plist")" = "$FEED" ] \
  || fail "the app doesn't carry the update feed $FEED"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$VERSION" ] \
  || fail "the app's version isn't $VERSION"

step "Making Lostty.dmg"
rm -rf "$OUT/dmg" "$OUT/Lostty.dmg"
mkdir -p "$OUT/dmg"
cp -R "$APP" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -volname Lostty -srcfolder "$OUT/dmg" -fs HFS+ -format UDZO "$OUT/Lostty.dmg" \
  > "$OUT/dmg.log" 2>&1 || failed "$OUT/dmg.log" "hdiutil failed"
codesign --sign "$IDENTITY" --timestamp "$OUT/Lostty.dmg" 2> "$OUT/dmg-sign.log" \
  || failed "$OUT/dmg-sign.log" "signing the DMG failed"

step "Notarizing (a few minutes)"
xcrun notarytool submit "$OUT/Lostty.dmg" --keychain-profile "$PROFILE" --wait --output-format json \
  > "$OUT/notary.json" 2> "$OUT/notary.log" || true
field() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))' "$OUT/notary.json" "$1" 2> /dev/null || true; }
if [ "$(field status)" != Accepted ]; then
  ID=$(field id)
  [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" "$OUT/notary-log.json" > /dev/null 2>&1 \
    && head -40 "$OUT/notary-log.json" >&2
  fail "Apple didn't notarize it (status: $(field status)); see $OUT/notary.log and $OUT/notary-log.json"
fi
xcrun stapler staple "$OUT/Lostty.dmg" > "$OUT/staple.log" 2>&1 || failed "$OUT/staple.log" "stapling failed"
spctl -a -t open --context context:primary-signature -v "$OUT/Lostty.dmg" > "$OUT/spctl.log" 2>&1 \
  || failed "$OUT/spctl.log" "Gatekeeper rejects the DMG"
MOUNT=$(mktemp -d)
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$OUT/Lostty.dmg" > /dev/null
if spctl -a -vv "$MOUNT/Lostty.app" > "$OUT/spctl-app.log" 2>&1 \
    && grep -q "Notarized Developer ID" "$OUT/spctl-app.log"; then OK=1; else OK=0; fi
hdiutil detach "$MOUNT" -quiet || true
[ "$OK" = 1 ] || failed "$OUT/spctl-app.log" "Gatekeeper rejects the app in the DMG"

step "Writing the update feed"
SIGNED=$("$SPARKLE_BIN/sign_update" "$OUT/Lostty.dmg") || fail "sign_update failed"
MIN=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")
$HELPER appcast --version "$VERSION" --build "$BUILD" --min-system "$MIN" --notes-file "$NOTES" \
  --url "https://github.com/$REPO/releases/download/$TAG/Lostty.dmg" --sign-output "$SIGNED" \
  > "$OUT/appcast.xml" || exit 1

if [ "$DRY_RUN" = 1 ]; then
  echo "Dry run: $OUT/Lostty.dmg and $OUT/appcast.xml are ready. Nothing was published."
  exit 0
fi

step "Publishing Lostty $VERSION"
git tag -a "$TAG" -m "Lostty $VERSION"
GIT_NO_REPLACE_OBJECTS=1 git push origin "refs/tags/$TAG" > "$OUT/push.log" 2>&1 \
  || failed "$OUT/push.log" "couldn't push the tag $TAG; nothing was published"
gh release create "$TAG" "$OUT/Lostty.dmg" "$OUT/appcast.xml" --repo "$REPO" --verify-tag \
  --title "Lostty $VERSION" --notes-file "$NOTES" > "$OUT/gh.log" 2>&1 || {
  cat "$OUT/gh.log" >&2
  fail "the tag $TAG is on GitHub, but the release wasn't created. Retry with: gh release create $TAG '$OUT/Lostty.dmg' '$OUT/appcast.xml' --repo $REPO --verify-tag --title 'Lostty $VERSION' --notes-file '$NOTES'"
}
curl -fsSL "$FEED" | grep -q "<sparkle:shortVersionString>$VERSION<" \
  || fail "released, but $FEED doesn't show $VERSION yet; check https://github.com/$REPO/releases"
echo "Released Lostty $VERSION: https://github.com/$REPO/releases/tag/$TAG"
