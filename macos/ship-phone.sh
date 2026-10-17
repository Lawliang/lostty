#!/bin/sh
# Builds the iPhone app (Release, development-signed for the team's phones)
# and installs it on the phone over the cable, else over Wi-Fi. When the Mac
# can't reach the phone either way, it publishes the build on this Mac's
# Tailscale address for an over-the-air install instead: open
# https://<this Mac>.<tailnet>.ts.net/ on the phone, tap Install. Needs HTTPS
# certificates on for the tailnet (Tailscale admin console: DNS > HTTPS
# Certificates), and serves to the tailnet only.
#
#   macos/ship-phone.sh ["What's new line" ...]
set -eu

# Leaves a build note for Lostty on this Mac to show on the phone (🔔): the
# build, its install link, and the terminal that shipped it, in its colors.
# Skipped when this Mac's Lostty keeps no notes.
note_build() { # app bundle-id build commit branch install-link
  inbox="$HOME/Library/Application Support/Lostty/notifications/inbox"
  [ -d "$inbox" ] || return 0
  session=""; title=""; skin=""
  if [ -n "${TMUX_PANE:-}" ]; then
    session=$(tmux display-message -p -t "$TMUX_PANE" '#{session_id}' 2>/dev/null || true)
    title=$(tmux display-message -p -t "$TMUX_PANE" '#{?@lostty_label,#{@lostty_label},#{pane_title}}' 2>/dev/null || true)
    skin=$(tmux display-message -p -t "$TMUX_PANE" '#{@lostty_skin}' 2>/dev/null || true)
  fi
  project=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
  python3 -I -c '
import json, os, sys, uuid
inbox, app, bundle, build, commit, branch, link, project, session, title, skin = sys.argv[1:]
drop = {"type": "build", "app": app, "bundleID": bundle, "build": build, "commit": commit,
        "branch": branch, "project": project, "installURL": link,
        "sessionID": session or None, "terminal": title or None, "skin": skin or None}
name = "build-%s.json" % str(uuid.uuid4()).upper()
with open(os.path.join(inbox, "." + name), "w") as f:
    json.dump(drop, f)
os.replace(os.path.join(inbox, "." + name), os.path.join(inbox, name))
' "$inbox" "$1" "$2" "$3" "$4" "$5" "$6" "$project" "$session" "$title" "$skin" || true
}
cd "$(dirname "$0")/.."
export PATH="$(brew --prefix zig@0.15)/bin:$PATH"

TEAM=K85Z63QH48
BUNDLE=com.lawliang.lostty-mobile
PORT=8765
OUT="$PWD/macos/build/phone-ship"
WWW="$OUT/www"
BUILD=$(date +%Y%m%d%H%M)
COMMIT=$(git rev-parse --short HEAD)
[ -z "$(git status --porcelain)" ] || COMMIT="$COMMIT-dirty"
BRANCH=$(git branch --show-current)
# The title of the terminal that shipped it, as the phone's list shows it:
# a name you typed, else Claude's task.
TERMINAL=""
if [ -n "${TMUX_PANE:-}" ]; then
  TERMINAL=$(tmux display-message -p -t "$TMUX_PANE" \
    '#{?@lostty_label,#{@lostty_label},#{pane_title}}' 2>/dev/null || true)
fi

# Stay awake while building, even with the lid closed on power.
caffeinate -is -w $$ &

mkdir -p "$WWW"
zig build -Demit-macos-app=false -Doptimize=ReleaseFast
echo "Archiving build $BUILD ($COMMIT)…"
xcodebuild archive \
  -project macos/Lostty.xcodeproj -scheme Lostty-iOS -configuration Release \
  -destination generic/platform=iOS -archivePath "$OUT/Lostty.xcarchive" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=$TEAM CURRENT_PROJECT_VERSION="$BUILD" \
  > "$OUT/archive.log" 2>&1 || { tail -20 "$OUT/archive.log"; echo "Archive failed; see $OUT/archive.log" >&2; exit 1; }

cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>debugging</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>thinning</key><string>&lt;none&gt;</string>
</dict></plist>
EOF
rm -rf "$OUT/export"
xcodebuild -exportArchive -archivePath "$OUT/Lostty.xcarchive" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates \
  > "$OUT/export.log" 2>&1 || { tail -20 "$OUT/export.log"; echo "Export failed; see $OUT/export.log" >&2; exit 1; }

cp "$OUT/export/"*.ipa "$OUT/Lostty.ipa"

# The phone gets the build the most direct way the Mac can reach it: over
# the cable, else over Wi-Fi (the same network; the phone needs "Connect via
# network" on in Xcode's Devices window), and only then a Tailscale page.
install_on_phone() { # how
  xcrun devicectl device install app --device "$PHONE" --timeout 180 "$OUT/Lostty.ipa" \
    > "$OUT/install.log" 2>&1 || return 1
  echo "Installed build $BUILD ($COMMIT) on the phone over $1."
  exit 0
}
# The paired iPhone and how it's connected now: "wired", "localNetwork", or
# nothing when the Mac doesn't see it (asleep, or away).
PHONE=""; TRANSPORT=""
if xcrun devicectl list devices --json-output "$OUT/devices.json" >/dev/null 2>&1; then
  read -r PHONE TRANSPORT <<EOF
$(python3 -I -c '
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    c = d["connectionProperties"]
    if d["hardwareProperties"].get("deviceType") == "iPhone" and c.get("pairingState") == "paired":
        available = c.get("tunnelState") != "unavailable"
        print(d["identifier"], (c.get("transportType") if available else None) or ""); break' "$OUT/devices.json")
EOF
fi
if [ -z "$PHONE" ]; then
  echo "No iPhone is paired with this Mac; publishing it over Tailscale."
else
  if [ "$TRANSPORT" = wired ]; then
    install_on_phone "the cable" \
      || echo "Couldn't install over the cable (see $OUT/install.log); trying Wi-Fi."
  else
    echo "The phone isn't on the cable; trying Wi-Fi."
  fi
  # A phone that just woke can take a few seconds to show up on the network;
  # any other failure isn't worth repeating.
  for try in 1 2 3 4; do
    install_on_phone "Wi-Fi" || true
    grep -q "unable to locate a device" "$OUT/install.log" || break
    [ "$try" = 4 ] || sleep 5
  done
  echo "Couldn't reach the phone over Wi-Fi (see $OUT/install.log); publishing it over Tailscale."
fi

HOST=$(tailscale status --json | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
URL="https://$HOST"

# A new name per build, so neither iOS nor Safari reuses a cached one.
cp "$OUT/Lostty.ipa" "$WWW/Lostty-$BUILD.ipa"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
  "$OUT/Lostty.xcarchive/Products/Applications/Lostty.app/Info.plist")
ICON=macos/Assets.xcassets/LosttyPhoneIcon.appiconset/LosttyPhoneIcon-1024.png
for size in 57 180 512; do
  sips -Z $size "$ICON" --out "$WWW/icon-$size.png" >/dev/null
done
# The manifest, the install page and latest.json; keeps the last three
# builds. Each argument to this script is a line under "What's new".
for note do shift; set -- "$@" --note "$note"; done
python3 -I macos/ship-phone-page.py "$WWW" "$URL" "$BUNDLE" --name Lostty --mascot \
  --build "$BUILD" --commit "$COMMIT" --version "$VERSION" \
  --branch "$BRANCH" --terminal "$TERMINAL" "$@"

# Serve: a local web server for the folder, and Tailscale in front of it
# for HTTPS on the tailnet. Both outlive this script.
if ! lsof -nP -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
  nohup python3 -m http.server $PORT --bind 127.0.0.1 --directory "$WWW" > "$OUT/server.log" 2>&1 &
fi
tailscale serve --bg $PORT >/dev/null
echo "Published build $BUILD ($COMMIT): $URL/"

# Not on the phone yet: a note on it (🔔) carries the install link.
note_build Lostty "$BUNDLE" "$BUILD" "$COMMIT" "$BRANCH" \
  "itms-services://?action=download-manifest&url=$URL/manifest-$BUILD.plist"
