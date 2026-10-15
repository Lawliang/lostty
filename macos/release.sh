#!/bin/sh
# Publishes Lostty for Mac: builds it, signs it as Developer ID, makes the
# DMG, has Apple notarize it, writes Sparkle's feed, then tags it and creates
# the GitHub release. A stable release also publishes its matching Lostty
# Beta (CONTRIBUTING.md → Stable and beta). Run it only when the owner says
# "release". One-time setup: CONTRIBUTING.md → Release.
#   macos/release.sh [--version X.Y] [--dry-run]   stable X.Y, then X.Y beta 1
#   macos/release.sh --beta [--dry-run]             the next beta of the latest stable
#   macos/release.sh --make-key                     the update-signing key, into the app
#   --dry-run: everything but publishing
set -eu
cd "$(dirname "$0")/.."
export PATH="$(brew --prefix zig@0.15)/bin:$PATH"

TEAM=K85Z63QH48
REPO=Lawliang/lostty
FEED="https://github.com/$REPO/releases/latest/download/appcast.xml"
BETA_FEED="https://github.com/$REPO/releases/download/beta/appcast-beta.xml"
PROFILE=lostty-notary
PLIST=macos/Lostty-Info.plist
OUT="$PWD/macos/build/release"
DERIVED="$OUT/DerivedData"
SPARKLE_BIN="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin"
HELPER="python3 -I macos/release_helper.py"

OVERRIDE=""; DRY_RUN=0; MAKE_KEY=0; BETA_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version) OVERRIDE=${2:?"--version needs X.Y"}; shift 2 ;;
    --beta) BETA_ONLY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --make-key) MAKE_KEY=1; shift ;;
    *) echo "Usage: macos/release.sh [--version X.Y | --beta] [--dry-run] | --make-key" >&2; exit 2 ;;
  esac
done
mkdir -p "$OUT"

# Set once stable is out, so a failure after it says how to finish the beta.
STABLE_OUT=0
fail() {
  echo "release: $*" >&2
  [ "$STABLE_OUT" = 0 ] || echo "release: Lostty $VERSION is out; publish its beta with: macos/release.sh --beta" >&2
  exit 1
}
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

[ "$BETA_ONLY" = 0 ] || [ -z "$OVERRIDE" ] || fail "--version names a stable release; a beta takes the latest stable's."

step "Checking"
[ -z "$(git status --porcelain)" ] || fail "commit or stash your changes first."
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
  || fail "this commit isn't GitHub's main. Push it to main (or check out origin/main) first."
COMMIT=$(git rev-parse HEAD)
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

# Stable's "latest" skips pre-releases, so betas never count toward it.
STABLE_LATEST=$(gh release list --repo "$REPO" --limit 1 --exclude-drafts --exclude-pre-releases \
  --json tagName --jq '.[0].tagName // ""')
TAGS=$(gh release list --repo "$REPO" --limit 1000 --exclude-drafts --json tagName --jq '.[].tagName')
if [ "$BETA_ONLY" = 1 ]; then
  [ -n "$STABLE_LATEST" ] || fail "make a stable release first: betas are numbered after it."
  VERSION=${STABLE_LATEST#v}
  BETA=$(echo "$TAGS" | $HELPER next-beta --stable "$STABLE_LATEST") || exit 1
  # Notes since the last release of either kind.
  SINCE=$(echo "$TAGS" | $HELPER newest-tag)
  NAME="Lostty $VERSION beta $BETA"
else
  VERSION=$($HELPER next-version --latest "$STABLE_LATEST" --override "$OVERRIDE") || exit 1
  BETA=1
  SINCE=$STABLE_LATEST
  NAME="Lostty $VERSION"
fi
TAG="v$VERSION"
BETA_TAG="v$VERSION-beta.$BETA"
BUILD=$(date +%Y%m%d%H%M)
if [ "$BETA_ONLY" = 0 ] && git rev-parse -q --verify "refs/tags/$TAG" > /dev/null; then
  fail "the tag $TAG already exists on this Mac."
fi
! git rev-parse -q --verify "refs/tags/$BETA_TAG" > /dev/null || fail "the tag $BETA_TAG already exists on this Mac."

# The matching beta reuses stable's notes; a beta by itself gets its own.
step "Notes for $NAME"
NOTES="$OUT/notes.md"
RANGE="-30 HEAD"
if [ -n "$SINCE" ]; then
  git fetch -q origin "refs/tags/$SINCE:refs/tags/$SINCE" 2> /dev/null || true
  git rev-parse -q --verify "refs/tags/$SINCE" > /dev/null && RANGE="$SINCE..HEAD"
fi
# shellcheck disable=SC2086 # RANGE is one or two words on purpose
git log --no-merges --format=%s $RANGE | $HELPER notes > "$NOTES"
${EDITOR:-nano} "$NOTES"
grep -q '[^[:space:]]' "$NOTES" || fail "the notes are empty; nothing was released."

step "Building the engine"
zig build -Demit-macos-app=false -Doptimize=ReleaseFast > "$OUT/zig.log" 2>&1 \
  || failed "$OUT/zig.log" "the engine build failed"
cat > "$OUT/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
EOF

# build_dmg stable|beta: archives, signs, notarizes and staples one build in
# $OUT/<channel>, then writes its feed there. Stable: Lostty.dmg and
# appcast.xml. Beta: Lostty-Beta.dmg and appcast-beta.xml, its enclosure on
# the versioned pre-release so an offered update outlives the next beta.
build_dmg() {
  CH=$1
  DIR="$OUT/$CH"
  if [ "$CH" = beta ]; then
    DMG=Lostty-Beta.dmg; FEED_FILE=appcast-beta.xml; VOLUME="Lostty Beta"
    CH_FEED=$BETA_FEED; CH_TAG=$BETA_TAG; CH_NAME="Lostty $VERSION beta $BETA"; WANT=beta
    set -- LOSTTY_CHANNEL=beta LOSTTY_BETA_NUMBER="$BETA" "INFOPLIST_KEY_CFBundleDisplayName=Lostty Beta" \
      ASSETCATALOG_COMPILER_APPICON_NAME=LosttyMacBetaIcon
  else
    DMG=Lostty.dmg; FEED_FILE=appcast.xml; VOLUME=Lostty
    CH_FEED=$FEED; CH_TAG=$TAG; CH_NAME="Lostty $VERSION"; WANT=""
    set --
  fi
  step "Building $CH_NAME ($BUILD)"
  rm -rf "$DIR"
  mkdir -p "$DIR"
  xcodebuild archive -project macos/Lostty.xcodeproj -scheme Lostty -configuration Release \
    -destination generic/platform=macOS -archivePath "$DIR/Lostty.xcarchive" -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates DEVELOPMENT_TEAM=$TEAM CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" LOSTTY_UPDATE_FEED="$CH_FEED" \
    ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO "$@" \
    > "$DIR/archive.log" 2>&1 || failed "$DIR/archive.log" "the $CH archive failed"
  xcodebuild -exportArchive -archivePath "$DIR/Lostty.xcarchive" -exportPath "$DIR/export" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates \
    > "$DIR/export.log" 2>&1 || failed "$DIR/export.log" "signing the $CH build as Developer ID failed"
  APP="$DIR/export/Lostty.app"
  codesign --verify --deep --strict "$APP" 2> "$DIR/codesign.log" || failed "$DIR/codesign.log" "the signature doesn't verify"
  # Notarization needs every helper (Sparkle's Autoupdate, Updater.app, its
  # XPC services) signed as Developer ID with a timestamp, not just the app.
  # (Not the symlinks inside Sparkle.framework, nor resource bundles with no code.)
  { echo "$APP"; find "$APP/Contents" ! -type l \( -name "*.app" -o -name "*.xpc" -o -name "*.framework" \
    -o -name "*.plugin" -o -name "*.bundle" -o -name Autoupdate \) -print; } > "$DIR/signed-parts.txt"
  while read -r part; do
    case "$part" in *.bundle | *.plugin) [ -d "$part/Contents/MacOS" ] || continue ;; esac
    codesign -dvv "$part" > "$DIR/part.log" 2>&1
    grep -q "^Authority=Developer ID Application" "$DIR/part.log" && grep -q "^Timestamp=" "$DIR/part.log" \
      || failed "$DIR/part.log" "${part#"$DIR/export/"} isn't signed as Developer ID with a timestamp"
  done < "$DIR/signed-parts.txt"
  INFO="$APP/Contents/Info.plist"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :LosttyUpdateFeed' "$INFO")" = "$CH_FEED" ] \
    || fail "the $CH app doesn't carry the update feed $CH_FEED"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")" = "$VERSION" ] \
    || fail "the $CH app's version isn't $VERSION"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :LosttyChannel' "$INFO")" = "$WANT" ] \
    || fail "the $CH app isn't the $CH channel"

  step "Making $DMG"
  rm -rf "$DIR/dmg"
  mkdir -p "$DIR/dmg"
  cp -R "$APP" "$DIR/dmg/"
  ln -s /Applications "$DIR/dmg/Applications"
  hdiutil create -volname "$VOLUME" -srcfolder "$DIR/dmg" -fs HFS+ -format UDZO "$DIR/$DMG" \
    > "$DIR/dmg.log" 2>&1 || failed "$DIR/dmg.log" "hdiutil failed"
  codesign --sign "$IDENTITY" --timestamp "$DIR/$DMG" 2> "$DIR/dmg-sign.log" \
    || failed "$DIR/dmg-sign.log" "signing the DMG failed"

  step "Notarizing $DMG (a few minutes)"
  xcrun notarytool submit "$DIR/$DMG" --keychain-profile "$PROFILE" --wait --output-format json \
    > "$DIR/notary.json" 2> "$DIR/notary.log" || true
  if [ "$(field status)" != Accepted ]; then
    ID=$(field id)
    [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" "$DIR/notary-log.json" > /dev/null 2>&1 \
      && head -40 "$DIR/notary-log.json" >&2
    fail "Apple didn't notarize $DMG (status: $(field status)); see $DIR/notary.log and $DIR/notary-log.json"
  fi
  xcrun stapler staple "$DIR/$DMG" > "$DIR/staple.log" 2>&1 || failed "$DIR/staple.log" "stapling failed"
  spctl -a -t open --context context:primary-signature -v "$DIR/$DMG" > "$DIR/spctl.log" 2>&1 \
    || failed "$DIR/spctl.log" "Gatekeeper rejects the DMG"
  MOUNT=$(mktemp -d)
  hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$DIR/$DMG" > /dev/null
  if spctl -a -vv "$MOUNT/Lostty.app" > "$DIR/spctl-app.log" 2>&1 \
      && grep -q "Notarized Developer ID" "$DIR/spctl-app.log"; then OK=1; else OK=0; fi
  hdiutil detach "$MOUNT" -quiet || true
  [ "$OK" = 1 ] || failed "$DIR/spctl-app.log" "Gatekeeper rejects the app in $DMG"

  step "Writing $FEED_FILE"
  SIGNED=$("$SPARKLE_BIN/sign_update" "$DIR/$DMG") || fail "sign_update failed"
  MIN=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO")
  if [ "$CH" = beta ]; then set -- --beta-number "$BETA"; else set --; fi
  $HELPER appcast --version "$VERSION" --build "$BUILD" --min-system "$MIN" --notes-file "$NOTES" \
    --url "https://github.com/$REPO/releases/download/$CH_TAG/$DMG" --sign-output "$SIGNED" "$@" \
    > "$DIR/$FEED_FILE" || exit 1
}
# A field of the last notarization's answer ($DIR/notary.json).
field() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))' "$DIR/notary.json" "$1" 2> /dev/null || true; }

[ "$BETA_ONLY" = 1 ] || build_dmg stable
build_dmg beta

if [ "$DRY_RUN" = 1 ]; then
  [ "$BETA_ONLY" = 1 ] || echo "Dry run: $OUT/stable/Lostty.dmg and $OUT/stable/appcast.xml ($TAG)."
  echo "Dry run: $OUT/beta/Lostty-Beta.dmg and $OUT/beta/appcast-beta.xml ($BETA_TAG, then the beta release)."
  echo "Nothing was published."
  exit 0
fi

# push_tag TAG MESSAGE: tags this commit and pushes it; a tag that never
# reached GitHub goes, so the next run can make it again.
push_tag() {
  git tag -a "$1" -m "$2" "$COMMIT"
  if ! GIT_NO_REPLACE_OBJECTS=1 git push origin "refs/tags/$1" > "$OUT/push.log" 2>&1; then
    git tag -d "$1" > /dev/null
    failed "$OUT/push.log" "couldn't push the tag $1; it wasn't published"
  fi
}

if [ "$BETA_ONLY" = 0 ]; then
  step "Publishing Lostty $VERSION"
  push_tag "$TAG" "Lostty $VERSION"
  gh release create "$TAG" "$OUT/stable/Lostty.dmg" "$OUT/stable/appcast.xml" --repo "$REPO" --verify-tag \
    --title "Lostty $VERSION" --notes-file "$NOTES" > "$OUT/gh.log" 2>&1 || {
    cat "$OUT/gh.log" >&2
    fail "the tag $TAG is on GitHub, but the release wasn't created. Retry with: gh release create $TAG '$OUT/stable/Lostty.dmg' '$OUT/stable/appcast.xml' --repo $REPO --verify-tag --title 'Lostty $VERSION' --notes-file '$NOTES'"
  }
  curl -fsSL "$FEED" | grep -q "<sparkle:shortVersionString>$VERSION<" \
    || fail "released, but $FEED doesn't show $VERSION yet; check https://github.com/$REPO/releases"
  echo "Released Lostty $VERSION: https://github.com/$REPO/releases/tag/$TAG"
  STABLE_OUT=1
fi

BETA_NAME="Lostty $VERSION beta $BETA"
step "Publishing $BETA_NAME"
push_tag "$BETA_TAG" "$BETA_NAME"
gh release create "$BETA_TAG" "$OUT/beta/Lostty-Beta.dmg" "$OUT/beta/appcast-beta.xml" --repo "$REPO" \
  --verify-tag --prerelease --title "$BETA_NAME" --notes-file "$NOTES" > "$OUT/gh-beta.log" 2>&1 || {
  cat "$OUT/gh-beta.log" >&2
  fail "the tag $BETA_TAG is on GitHub, but its release wasn't created. Retry with: gh release create $BETA_TAG '$OUT/beta/Lostty-Beta.dmg' '$OUT/beta/appcast-beta.xml' --repo $REPO --verify-tag --prerelease --title '$BETA_NAME' --notes-file '$NOTES', then run this script's beta release step by hand: gh release upload beta … --clobber"
}
# The beta feed's fixed home: the newest beta's DMG and feed, replaced each time.
if gh release view beta --repo "$REPO" > /dev/null 2>&1; then
  { gh release upload beta "$OUT/beta/Lostty-Beta.dmg" "$OUT/beta/appcast-beta.xml" --repo "$REPO" --clobber \
    && gh release edit beta --repo "$REPO" --title "Lostty Beta ($VERSION beta $BETA)" --notes-file "$NOTES"; } \
    > "$OUT/gh-beta-feed.log" 2>&1 || failed "$OUT/gh-beta-feed.log" "$BETA_NAME is out, but the beta release wasn't refreshed"
else
  gh release create beta "$OUT/beta/Lostty-Beta.dmg" "$OUT/beta/appcast-beta.xml" --repo "$REPO" \
    --prerelease --latest=false --target "$COMMIT" --title "Lostty Beta ($VERSION beta $BETA)" \
    --notes-file "$NOTES" > "$OUT/gh-beta-feed.log" 2>&1 \
    || failed "$OUT/gh-beta-feed.log" "$BETA_NAME is out, but the beta release wasn't created"
fi
curl -fsSL "$BETA_FEED" | grep -q "<sparkle:shortVersionString>$VERSION beta $BETA<" \
  || fail "released, but $BETA_FEED doesn't show $VERSION beta $BETA yet; check https://github.com/$REPO/releases/tag/beta"
echo "Released $BETA_NAME: https://github.com/$REPO/releases/tag/beta"
