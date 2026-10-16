#!/bin/sh
# Sets up this Mac to build Lostty, then builds and installs it: points the
# command line at Xcode, adds the Metal Toolchain, Zig and tmux when they're
# missing, and runs install.sh --stable (the finished build). Safe to run again.
#   --tools-only: just the tools (for the iPhone app, with Lostty for Mac downloaded)
set -eu
cd "$(dirname "$0")/.."

XCODE=/Applications/Xcode.app
if [ ! -d "$XCODE" ]; then
  echo "Install Xcode 26 from the App Store, open it once, then run this again:" >&2
  echo "  https://apps.apple.com/app/xcode/id497799835" >&2
  exit 1
fi
VERSION=$("$XCODE/Contents/Developer/usr/bin/xcodebuild" -version | sed -n 's/^Xcode \([0-9]*\).*/\1/p')
if [ "${VERSION:-0}" -lt 26 ]; then
  echo "Lostty needs Xcode 26 or later; this Mac has Xcode $VERSION. Update it from the App Store." >&2
  exit 1
fi

if [ "$(xcode-select -p)" != "$XCODE/Contents/Developer" ]; then
  echo "Pointing the command line at Xcode (asks for your password)…"
  sudo xcode-select --switch "$XCODE"
fi
if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  echo "Finishing Xcode's first launch (asks for your password)…"
  sudo xcodebuild -license accept
  sudo xcodebuild -runFirstLaunch
fi
if ! xcrun -f metal >/dev/null 2>&1; then
  echo "Downloading the Metal Toolchain…"
  xcodebuild -downloadComponent MetalToolchain
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Install Homebrew from https://brew.sh, then run this again." >&2
  exit 1
fi
for formula in zig@0.15 tmux; do
  brew list --versions "$formula" >/dev/null 2>&1 || brew install "$formula"
done

if [ "${1:-}" = "--tools-only" ]; then
  echo "The tools are ready. For the iPhone app: macos/install-phone.sh"
  exit 0
fi
macos/install.sh --stable
if ! pgrep -xf /Applications/Lostty.app/Contents/MacOS/lostty >/dev/null; then
  open /Applications/Lostty.app
fi
