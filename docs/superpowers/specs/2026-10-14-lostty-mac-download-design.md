# Lostty for Mac as one download — design

Date: 2026-10-14. Status: approved in conversation; this spec awaits review.

## 1. Goal

A new user installs Lostty on a Mac the way they install Ghostty: one link,
download, drag to Applications, open. No Xcode, no Homebrew, no build. Copies
installed that way update themselves. Building from source stays, for people
changing the code (CONTRIBUTING.md).

Out of scope: the iPhone app (TestFlight is a later project), GitHub Actions,
a website.

## 2. Decisions (from the owner)

- **Releases happen when the owner says so.** One script on the owner's Mac
  builds, signs, notarizes and publishes. The Developer ID certificate never
  leaves that Mac; GitHub holds no secrets.
- **Installed copies check daily and ask first.** A new release shows "Update
  available"; one click downloads it and restarts Lostty with its terminals
  kept. Nothing installs without a click.
- **Versions go 0.2, 0.3, …** Each release bumps the minor version by one
  (the app says 0.1 today). The owner can name a bigger jump (`1.0`).
- **The update feed travels with the release** (option 1 of 3): every GitHub
  release carries `Lostty.dmg` and `appcast.xml`, and Lostty reads
  `https://github.com/Lawliang/lostty/releases/latest/download/appcast.xml`,
  which always means the newest release. No server, and releasing needs no
  commit. Rejected: a feed in the repo (a commit per release), and our own
  updater (re-doing Sparkle's signature checks).

## 3. One-time setup (the owner, guided)

1. **Developer ID Application certificate** for team K85Z63QH48: Xcode →
   Settings → Accounts → Manage Certificates → + → Developer ID Application.
   Only the team's Account Holder can create it.
2. **Notarization login**: an app-specific password from account.apple.com,
   saved once with `xcrun notarytool store-credentials lostty-notary`
   (Apple ID, team K85Z63QH48, that password). It lives in the keychain.
3. **Update-signing key**: `macos/release.sh --make-key` runs Sparkle's
   `generate_keys`, which keeps the private key in the login keychain and
   prints the public key. That public key replaces `SUPublicEDKey` in
   `macos/Lostty-Info.plist` (today it is Ghostty's, never used because no
   feed is set). Committed like any change.

`macos/release.sh` checks each of these first and says which one is missing
and how to add it.

## 4. `macos/release.sh`

```
macos/release.sh [--version X.Y] [--dry-run]
macos/release.sh --make-key
```

In order, stopping at the first failure with what went wrong:

1. **Preconditions.** On `main`, working tree clean, `HEAD` equal to
   `origin/main` after a fetch; `gh` signed in; the three setup items
   present (`security find-identity` lists "Developer ID Application" for
   K85Z63QH48; `notarytool history --keychain-profile lostty-notary`
   works; `generate_keys -p` prints a key equal to the Info.plist's).
2. **Version.** The latest release from `gh release list` (not git tags: the
   local `v1.3.1` is Ghostty's), `vX.Y` → `X.(Y+1)`; none yet → `0.2`.
   `--version` overrides; it must be greater than the latest. Build number:
   `date +%Y%m%d%H%M`, always rising, the same scheme as the phone builds.
3. **Notes.** Commit subjects since the last release's tag (or the last 30
   when there is none), the `lostty: ` prefix dropped and `docs:` commits
   left out, as a bulleted list in a temp file opened in `$EDITOR` (default
   `nano`). An empty file stops the release.
4. **Build.** `zig build -Demit-macos-app=false -Doptimize=ReleaseFast`, then
   `xcodebuild archive` of the `Lostty` scheme, `Release` configuration
   (`Lostty.entitlements`, hardened runtime), with `MARKETING_VERSION`,
   `CURRENT_PROJECT_VERSION`, `LOSTTY_UPDATE_FEED` (§5) and code coverage
   off, then `-exportArchive` with method `developer-id`, which signs
   Sparkle's helpers and the dock-tile plugin as Developer ID too.
5. **DMG.** `hdiutil` makes `Lostty.dmg` (the app and an Applications
   shortcut), signed with the Developer ID certificate.
6. **Notarize.** `xcrun notarytool submit Lostty.dmg --keychain-profile
   lostty-notary --wait`; on "Invalid", print the notary log. Then
   `xcrun stapler staple` the DMG and check `spctl -a -t open --context
   context:primary-signature -v Lostty.dmg` and, from the mounted DMG,
   `spctl -a -vv Lostty.app` say "accepted … Notarized Developer ID".
7. **Feed.** Sparkle's `sign_update Lostty.dmg` gives the EdDSA signature and
   length; the script writes `appcast.xml` with one item: the version, build
   number, `minimumSystemVersion` from the app's `LSMinimumSystemVersion`,
   the notes as HTML, and the enclosure URL
   `https://github.com/Lawliang/lostty/releases/download/vX.Y/Lostty.dmg`.
8. **Publish** (skipped by `--dry-run`, which prints where the DMG and feed
   are instead). Tag `vX.Y` on `HEAD`, `git push origin vX.Y` (that tag only,
   never `--tags`), then `gh release create vX.Y Lostty.dmg appcast.xml
   --title "Lostty X.Y" --notes-file <notes>`. Last, check that
   `releases/latest/download/appcast.xml` serves the new version.

Sparkle's `generate_keys` and `sign_update` come from the Sparkle package
Xcode already resolves (its `bin/` in the package checkout under the
archive's DerivedData); the script finds them there.

Everything goes in `macos/build/release/` (git-ignored).

## 5. App changes

- **Feed only in release builds.** `Lostty-Info.plist` gains
  `LosttyUpdateFeed` = `$(LOSTTY_UPDATE_FEED)`. The build setting is empty
  in every configuration; only `release.sh` passes the URL. So the owner's
  `install.sh` and Debug builds never check, and a release can never replace
  them.
- `UpdateDriver.feedURLString(for:)` returns `LosttyUpdateFeed` when it is
  an `https://github.com/Lawliang/lostty/` URL, else nil (today: always
  nil). The comment about never reaching Ghostty's feed stays true.
- **Daily checks, ask first.** `SUEnableAutomaticChecks` leaves the
  Info.plist. In `AppDelegate`'s update sync: no feed → automatic checks and
  downloads off (today's behavior); a feed → automatic checks on, downloads
  off, unless the user's `auto-update` config says otherwise (`off`,
  `check`, `download` keep working). `SUScheduledCheckInterval` = 86400.
  Setting the property up front means Sparkle never shows its "check
  automatically?" prompt.
- **Install keeps terminals.** Sparkle's install already goes through
  `LosttyRestart.restart(reason: .sparkle)` (`AppDelegate` line ~467), which
  saves the restart handoff and marks the tmux sessions as restarting.
  Unchanged.
- **Check for Updates…** stays in the menu. Without a feed (local builds) it
  says "This copy of Lostty was built on this Mac; it updates with
  install.sh." instead of Sparkle's "no update information" error.

## 6. README and docs

- README "On your Mac" becomes one step: **Download Lostty**, a link to
  `https://github.com/Lawliang/lostty/releases/latest/download/Lostty.dmg`
  (always the newest), then open it and drag Lostty to Applications. The
  "You'll need" line drops Xcode for the Mac part. The iPhone steps stay as
  they are (they still need Xcode, until TestFlight).
- Updating: "Lostty checks for updates daily and asks before installing."
- CONTRIBUTING.md gains "Build from source" with `macos/setup.sh` (moved from
  the README) and "Release" with the one-time setup and `macos/release.sh`.

## 7. Errors

Every failing step prints the step, the command's last lines, and the log
path. Nothing is published unless every earlier step passed: the tag is
pushed only after notarization and the feed succeed. If `gh release create`
fails after the tag is pushed, the script says so and prints the command to
retry; it never deletes the tag on its own.

## 8. Testing

- **Unit tests:** `feedURLString` is nil with no `LosttyUpdateFeed`, with an
  empty one, and with a non-Lostty URL, and returns the Lostty URL; the
  update sync turns automatic checks on only with a feed and still honors
  `auto-update = off`; the "built on this Mac" message without a feed.
- **Script logic** (version bump, notes filtering, appcast XML) lives in a
  small Python helper (`macos/release-helper.py`, run with `python3 -I`)
  with its own tests (`python3 -I -m unittest macos/release-helper-test.py`).
- **Dry run** before the first real release: everything through the feed,
  then mount the DMG and open the app from it on this Mac (Gatekeeper must
  accept it with no warning).
- **First release 0.2**, then the README link downloads it.
- **The update itself** (0.2 → 0.3 keeping terminals) needs a Lostty that
  isn't the owner's working one: a second Mac or a guest account. That hand
  check is the owner's, after 0.3 is released.

## 9. Constraints carried from the repo

- Never `git push --tags`, never push `refs/replace`; push with
  `GIT_NO_REPLACE_OBJECTS=1`.
- Don't delete engine or other-platform code.
- Releasing is outward-facing: the script runs only when the owner says
  "release".
