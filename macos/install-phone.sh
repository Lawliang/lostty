#!/bin/sh
# Builds the iPhone app and installs it on the iPhone plugged into this Mac,
# signed with the Apple Account added in Xcode → Settings → Accounts.
#   --build-only        build and sign it, without a phone
#   LOSTTY_TEAM=…       the team to sign with (default: the account's team)
#   LOSTTY_BUNDLE_ID=…  the app's identifier (default: one made from the team)
set -eu
cd "$(dirname "$0")/.."
export PATH="$(brew --prefix zig@0.15)/bin:$PATH"
OUT="$PWD/macos/build/phone-install"
mkdir -p "$OUT"

# The team Xcode signs for with the account you added: a paid one first.
TEAM=${LOSTTY_TEAM:-$(defaults export com.apple.dt.Xcode - 2>/dev/null | python3 -I -c '
import plistlib, sys
prefs = plistlib.loads(sys.stdin.buffer.read())
teams = [t for ts in prefs.get("IDEProvisioningTeamByIdentifier", prefs.get("IDEProvisioningTeams", {})).values()
         for t in ts if t.get("teamID")]
teams.sort(key=lambda t: bool(t.get("isFreeProvisioningTeam")))
print(teams[0]["teamID"] if teams else "")' 2>/dev/null || true)}
if [ -z "$TEAM" ]; then
  echo "Add your Apple Account in Xcode → Settings → Accounts, then run this again." >&2
  exit 1
fi
# An identifier belongs to one team, so each team gets its own.
BUNDLE=${LOSTTY_BUNDLE_ID:-com.lostty.mobile.$(echo "$TEAM" | tr '[:upper:]' '[:lower:]')}

DESTINATION=generic/platform=iOS
if [ "${1:-}" != "--build-only" ]; then
  xcrun devicectl list devices --json-output "$OUT/devices.json" >/dev/null 2>&1 || true
  PHONE=$(python3 -I -c '
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
for d in devices:
    if d["hardwareProperties"].get("deviceType") == "iPhone" \
            and d["connectionProperties"].get("tunnelState") != "unavailable":
        print(d["identifier"], d["hardwareProperties"].get("udid", "")); break' "$OUT/devices.json")
  if [ -z "$PHONE" ]; then
    echo "Plug your iPhone into this Mac, unlock it and tap Trust, then run this again." >&2
    exit 1
  fi
  DEVICE=${PHONE% *}
  DESTINATION="id=${PHONE#* }"
fi

echo "Building the engine…"
zig build -Demit-macos-app=false -Doptimize=ReleaseFast
echo "Building the iPhone app for team ${TEAM} as ${BUNDLE}…"
xcodebuild build \
  -project macos/Lostty.xcodeproj -scheme Lostty-iOS -configuration Release \
  -destination "$DESTINATION" SYMROOT="$OUT" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" \
  > "$OUT/build.log" 2>&1 || { tail -20 "$OUT/build.log"; echo "Build failed; see $OUT/build.log" >&2; exit 1; }
APP=$(find "$OUT/Release-iphoneos" -maxdepth 1 -name "*.app" | head -1)
if [ "${1:-}" = "--build-only" ]; then
  echo "Built $APP"
  exit 0
fi

HINTS="On the iPhone, check that:
  - Settings → Privacy & Security → Developer Mode is on (the phone restarts);
  - your Apple Account is trusted in Settings → General → VPN & Device Management.
Then run this again."
xcrun devicectl device install app --device "$DEVICE" "$APP" > "$OUT/install.log" 2>&1 \
  || { tail -5 "$OUT/install.log"; echo "Couldn't install it. $HINTS" >&2; exit 1; }
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE" > "$OUT/launch.log" 2>&1 \
  || { echo "Installed, but it didn't open. $HINTS" >&2; exit 1; }
echo "Lostty is on your iPhone."
