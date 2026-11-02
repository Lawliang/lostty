#!/bin/sh
# How far an edition has changed Core (AGENTS.md → Editions): the lines it
# changes outside its own folders, since it last took in main.
#   macos/edition-core-diff.sh            this branch
#   macos/edition-core-diff.sh orca       edition/orca
set -eu
cd "$(dirname "$0")/.."
REF=HEAD
[ -n "${1:-}" ] && REF="edition/$1"
BASE=$(git merge-base main "$REF")
echo "Core files $REF changes (outside macos/Sources/Editions and src/cli/editions):"
git diff --stat "$BASE" "$REF" -- . ':(exclude)macos/Sources/Editions' ':(exclude)src/cli/editions' \
  ':(exclude)macos/Tests/Editions' | tail -40
