#!/bin/sh
# Runs the macOS unit tests with a clean environment (mirrors build.nu).
# Usage: macos/skins-test.sh [SuiteName]   e.g. macos/skins-test.sh SkinsTOMLTests
set -eu
cd "$(dirname "$0")"
mkdir -p build
ONLY=""
if [ $# -gt 0 ]; then ONLY="-only-testing:LosttyTests/$1"; fi
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  xcodebuild -project Lostty.xcodeproj -scheme Lostty -configuration Debug \
  SYMROOT="$PWD/build" -skip-testing LosttyUITests $ONLY test > build/last-test.log 2>&1 || true
grep -E "error:|✘|Test run with|\*\* TEST (SUCCEEDED|FAILED)" build/last-test.log || true
grep -q "\*\* TEST SUCCEEDED" build/last-test.log
