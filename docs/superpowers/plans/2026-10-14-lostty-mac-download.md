# Lostty for Mac as One Download Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new user installs Lostty for Mac from one link (a notarized `Lostty.dmg` on GitHub Releases), and installed copies check daily for updates and ask before installing.

**Architecture:** `macos/release.sh` (owner's Mac only) builds, Developer-ID-signs, notarizes and publishes `Lostty.dmg` + Sparkle's `appcast.xml` as a GitHub release; a stdlib Python helper does the testable parts (version, notes, appcast XML). The app reads its feed from an Info.plist key that only `release.sh` fills, so builds made on a Mac never check; Sparkle's existing install path already keeps terminals (`LosttyRestart.restart(reason: .sparkle)`).

**Tech Stack:** POSIX sh, Python 3 stdlib (`python3 -I`), Swift/Swift Testing, Sparkle 2 (already linked), `xcodebuild archive/-exportArchive`, `hdiutil`, `notarytool`, `stapler`, `spctl`, `gh`.

**Spec:** `docs/superpowers/specs/2026-10-14-lostty-mac-download-design.md`

## Global Constraints

- Team `K85Z63QH48`; repo `Lawliang/lostty`; feed `https://github.com/Lawliang/lostty/releases/latest/download/appcast.xml`; DMG asset name `Lostty.dmg`; notary keychain profile `lostty-notary`.
- Versions `X.Y`; first release `0.2`; each release bumps the minor by one unless `--version` names a later one. Build number `date +%Y%m%d%H%M`.
- The latest release comes from `gh release list`, never from git tags (the local `v1.3.1` is Ghostty's).
- Never `git push --tags`; push only `refs/tags/vX.Y`, with `GIT_NO_REPLACE_OBJECTS=1`. Never push `refs/replace`.
- Release builds check daily (`SUScheduledCheckInterval` 86400) and ask first; `auto-update` config (`off`/`check`/`download`) still wins. Builds without a feed (install.sh, Debug) never check.
- Nothing is published unless every earlier step passed; the tag is pushed only after notarization and the feed succeed; the script never deletes a tag.
- Releasing is outward-facing: `macos/release.sh` without `--dry-run` runs only when the owner says "release".
- Everything the release makes goes in `macos/build/release/` (git-ignored by `macos/.gitignore`'s `build/`).
- Don't open a second Lostty on the owner's Mac (same bundle ID as the running one).

## Review Focus

1. **Info.plist preprocessing eats the feed URL.** `INFOPLIST_PREPROCESS = YES` runs the C preprocessor, which treats `//` as a comment; the built app must carry the whole URL. Task 2 Step 6 builds with the setting and reads the built plist.
2. **Release from the wrong commit.** A dirty tree, or `HEAD` not equal to GitHub's `main` (the owner works on `skins` and pushes `skins:main`, so there's no local `main`), must stop with a plain message before anything builds. Task 4 Step 3 runs the preconditions on this repo as it is.
3. **Notes that break the feed.** A commit subject with `<`, `&` or `]]>` must still give valid XML. Task 1 tests it.
4. **Sparkle's nested helpers not Developer-ID signed.** Gatekeeper rejects the app if `Autoupdate`/XPC services keep an ad-hoc signature. `release.sh` checks `spctl` on the app inside the mounted DMG (Task 4); the owner's dry run (Task 6) is where it first runs for real.
5. **Tag pushed, release not created.** `gh release create` failing after the tag push must say so and print the retry command, never delete the tag. Code in Task 4 Step 2; read it in review.

---

### Task 1: The release helper

**Files:**
- Create: `macos/release_helper.py`
- Test: `macos/release_helper_test.py`

Ruling: named with underscores (spec: `release-helper.py`) so the test can load it as a module; `python3 -I` doesn't put the script's folder on `sys.path`, so the test loads it by path.

**Interfaces:**
- Produces (CLI, used by Task 4):
  - `python3 -I macos/release_helper.py next-version --latest TAG --override X.Y` → prints `X.Y`; exit 1 with `release: …` on stderr when invalid.
  - `python3 -I macos/release_helper.py notes` → commit subjects on stdin, `- …` bullets on stdout.
  - `python3 -I macos/release_helper.py appcast --version X.Y --build N --min-system V --notes-file F --url U --sign-output S` → `appcast.xml` on stdout.
- Python: `ReleaseError`, `next_version(latest: str, override: str) -> str`, `notes(subjects) -> list[str]`, `parse_sign_output(text) -> (str, int)`, `appcast(version, build, min_system, bullets, url, signature, length, now) -> str`.

- [ ] **Step 1: Write the failing tests**

`macos/release_helper_test.py`:

```python
"""Tests for release_helper.py: python3 -I macos/release_helper_test.py"""
import importlib.util
import pathlib
import unittest
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

_spec = importlib.util.spec_from_file_location(
    "release_helper", pathlib.Path(__file__).with_name("release_helper.py"))
helper = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(helper)

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


class NextVersion(unittest.TestCase):
    def test_the_first_release_is_0_2(self):
        self.assertEqual(helper.next_version("", ""), "0.2")

    def test_each_release_is_one_minor_step(self):
        self.assertEqual(helper.next_version("v0.2", ""), "0.3")
        self.assertEqual(helper.next_version("v0.9", ""), "0.10")

    def test_a_named_version_can_jump(self):
        self.assertEqual(helper.next_version("v0.3", "1.0"), "1.0")
        self.assertEqual(helper.next_version("", "1.0"), "1.0")

    def test_a_named_version_must_be_later(self):
        for override in ("0.3", "0.2"):
            with self.assertRaises(helper.ReleaseError):
                helper.next_version("v0.3", override)

    def test_other_shapes_are_refused(self):
        for bad in ("1", "1.2.3", "v", "abc"):
            with self.assertRaises(helper.ReleaseError):
                helper.next_version("", bad)
        with self.assertRaises(helper.ReleaseError):
            helper.next_version("v1.3.1", "")


class Notes(unittest.TestCase):
    def test_bullets_without_the_prefix_or_docs(self):
        self.assertEqual(helper.notes([
            "lostty: observer: short notes in plain words",
            "docs: spec the download",
            "",
            "Fix a crash",
        ]), ["- Observer: short notes in plain words", "- Fix a crash"])


class SignOutput(unittest.TestCase):
    def test_reads_signature_and_length(self):
        text = 'sparkle:edSignature="abc+/=" length="1234"\n'
        self.assertEqual(helper.parse_sign_output(text), ("abc+/=", 1234))

    def test_anything_else_is_an_error(self):
        with self.assertRaises(helper.ReleaseError):
            helper.parse_sign_output("Error: no key")


class Appcast(unittest.TestCase):
    def make(self, bullets):
        return helper.appcast(
            "0.2", "202610141200", "14.0", bullets,
            "https://github.com/Lawliang/lostty/releases/download/v0.2/Lostty.dmg",
            "sig==", 5678, datetime(2026, 10, 14, 12, 0, tzinfo=timezone.utc))

    def test_one_item_sparkle_can_read(self):
        item = ET.fromstring(self.make(["- Faster"])).find("channel/item")
        self.assertEqual(item.find("title").text, "Lostty 0.2")
        self.assertEqual(item.find(SPARKLE + "version").text, "202610141200")
        self.assertEqual(item.find(SPARKLE + "shortVersionString").text, "0.2")
        self.assertEqual(item.find(SPARKLE + "minimumSystemVersion").text, "14.0")
        self.assertEqual(item.find("pubDate").text, "Wed, 14 Oct 2026 12:00:00 +0000")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"),
                         "https://github.com/Lawliang/lostty/releases/download/v0.2/Lostty.dmg")
        self.assertEqual(enclosure.get("length"), "5678")
        self.assertEqual(enclosure.get(SPARKLE + "edSignature"), "sig==")
        self.assertEqual(item.find("description").text, "<ul><li>Faster</li></ul>")

    def test_notes_with_markup_stay_valid(self):
        item = ET.fromstring(self.make(["- Fix <tab> & ]]> parsing"])).find("channel/item")
        self.assertEqual(item.find("description").text,
                         "<ul><li>Fix &lt;tab&gt; &amp; ]]&gt; parsing</li></ul>")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them to see them fail**

Run: `python3 -I macos/release_helper_test.py`
Expected: FAIL with `FileNotFoundError` for `release_helper.py`.

- [ ] **Step 3: Write the helper**

`macos/release_helper.py`:

```python
"""Helper for macos/release.sh: the next version, the release notes and
Sparkle's appcast.xml. Standard library only; run with python3 -I.

  next-version --latest TAG --override X.Y   prints the version to release
  notes                                      commit subjects (stdin) → "- …" lines
  appcast --version X.Y --build N --min-system V --notes-file F --url U --sign-output S
"""
import argparse
import email.utils
import html
import re
import sys
from datetime import datetime, timezone

FIRST = "0.2"
VERSION = re.compile(r"^v?(\d+)\.(\d+)$")


class ReleaseError(Exception):
    pass


def parse_version(text):
    match = VERSION.match(text.strip())
    if not match:
        raise ReleaseError(f"{text!r} isn't a version like 0.2")
    return int(match.group(1)), int(match.group(2))


def next_version(latest, override):
    """After `latest` (a tag like v0.2, or "" before the first release): one
    minor step up, or `override` when it is later."""
    if override:
        wanted = parse_version(override)
        if latest and wanted <= parse_version(latest):
            raise ReleaseError(f"{override} isn't after {latest.lstrip('v')}")
        return "%d.%d" % wanted
    if not latest:
        return FIRST
    major, minor = parse_version(latest)
    return f"{major}.{minor + 1}"


def notes(subjects):
    """Bullets for the notes: `docs:` commits left out, the `lostty: `
    prefix dropped, the first letter capitalized."""
    bullets = []
    for subject in subjects:
        subject = subject.strip()
        if not subject or subject.startswith("docs:"):
            continue
        if subject.startswith("lostty: "):
            subject = subject[len("lostty: "):]
        bullets.append("- " + subject[0].upper() + subject[1:])
    return bullets


def parse_sign_output(text):
    """(signature, length) from sign_update's
    `sparkle:edSignature="…" length="…"`."""
    signature = re.search(r'sparkle:edSignature="([^"]+)"', text)
    length = re.search(r'\blength="(\d+)"', text)
    if not signature or not length:
        raise ReleaseError(f"sign_update printed {text.strip()!r}")
    return signature.group(1), int(length.group(1))


def appcast(version, build, min_system, bullets, url, signature, length, now):
    # Escaping turns any "]]>" into "]]&gt;", so the CDATA can't end early.
    items = "".join(
        "<li>%s</li>" % html.escape(b[2:] if b.startswith("- ") else b, quote=False)
        for b in bullets)
    return f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Lostty</title>
    <item>
      <title>Lostty {version}</title>
      <pubDate>{email.utils.format_datetime(now)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{min_system}</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>{items}</ul>]]></description>
      <enclosure url="{html.escape(url)}" length="{length}" type="application/octet-stream" sparkle:edSignature="{html.escape(signature)}"/>
    </item>
  </channel>
</rss>
"""


def main(argv):
    parser = argparse.ArgumentParser(prog="release_helper.py")
    commands = parser.add_subparsers(dest="command", required=True)
    version = commands.add_parser("next-version")
    version.add_argument("--latest", default="")
    version.add_argument("--override", default="")
    commands.add_parser("notes")
    feed = commands.add_parser("appcast")
    for name in ("--version", "--build", "--min-system", "--notes-file", "--url", "--sign-output"):
        feed.add_argument(name, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "next-version":
            print(next_version(args.latest, args.override))
        elif args.command == "notes":
            print("\n".join(notes(sys.stdin.read().splitlines())))
        else:
            with open(args.notes_file, encoding="utf-8") as file:
                bullets = [line.rstrip("\n") for line in file if line.strip()]
            signature, length = parse_sign_output(args.sign_output)
            sys.stdout.write(appcast(args.version, args.build, args.min_system, bullets,
                                     args.url, signature, length, datetime.now(timezone.utc)))
    except ReleaseError as error:
        print(f"release: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

- [ ] **Step 4: Run the tests**

Run: `python3 -I macos/release_helper_test.py`
Expected: `Ran 10 tests` … `OK`.

Then the CLI once: `printf 'lostty: a\ndocs: b\n' | python3 -I macos/release_helper.py notes && python3 -I macos/release_helper.py next-version --latest v0.3 --override 0.3; echo "exit $?"`
Expected: `- A`, then `release: 0.3 isn't after 0.3` and `exit 1`.

- [ ] **Step 5: Commit**

```bash
git add macos/release_helper.py macos/release_helper_test.py
git commit -m "lostty: release: version, notes and appcast helper

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The feed only in release builds

**Files:**
- Create: `macos/Sources/Features/Update/UpdateFeed.swift`
- Modify: `macos/Lostty-Info.plist` (after the `SUPublicEDKey` string)
- Modify: `macos/Sources/Features/Update/UpdateDelegate.swift:5-15`
- Test: `macos/Tests/Update/UpdateFeedTests.swift`

Ruling: no `LOSTTY_UPDATE_FEED` line in `project.pbxproj`. An undefined build setting expands to an empty string, which is "empty in every configuration" without touching four config blocks.

**Interfaces:**
- Produces: `enum UpdateFeed { static let infoKey: String; static let prefix: String; static func url(info: [String: Any]?) -> String?; static var current: String? }`. The project uses synchronized groups, so new files need no `project.pbxproj` edit.
- Produces: Info.plist key `LosttyUpdateFeed` = `$(LOSTTY_UPDATE_FEED)`, filled by `release.sh` (Task 4).

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Update/UpdateFeedTests.swift`:

```swift
#if os(macOS)
import Testing
@testable import Lostty

struct UpdateFeedTests {
    static let feed = "https://github.com/Lawliang/lostty/releases/latest/download/appcast.xml"

    @Test func aReleaseBuildHasItsFeed() {
        #expect(UpdateFeed.url(info: [UpdateFeed.infoKey: Self.feed]) == Self.feed)
    }

    @Test func aBuildMadeOnThisMacHasNone() {
        #expect(UpdateFeed.url(info: nil) == nil)
        #expect(UpdateFeed.url(info: [:]) == nil)
        #expect(UpdateFeed.url(info: [UpdateFeed.infoKey: ""]) == nil)
        #expect(UpdateFeed.url(info: [UpdateFeed.infoKey: "$(LOSTTY_UPDATE_FEED)"]) == nil)
    }

    @Test func onlyLosttysOwnFeed() {
        for other in [
            "https://release.files.ghostty.org/appcast.xml",
            "http://github.com/Lawliang/lostty/releases/latest/download/appcast.xml",
            "https://github.com/Lawliang/lostty-fork/releases/latest/download/appcast.xml",
            "https:",
        ] {
            #expect(UpdateFeed.url(info: [UpdateFeed.infoKey: other]) == nil)
        }
        #expect(UpdateFeed.url(info: [UpdateFeed.infoKey: 42]) == nil)
    }
}
#endif
```

- [ ] **Step 2: Run them to see them fail**

Run: `macos/skins-test.sh UpdateFeedTests`
Expected: FAIL to compile: `cannot find 'UpdateFeed' in scope`.

- [ ] **Step 3: Write `UpdateFeed`**

`macos/Sources/Features/Update/UpdateFeed.swift`:

```swift
import Foundation

/// Where this copy of Lostty looks for updates. `release.sh` builds the
/// feed into a release (`LosttyUpdateFeed`); a build made on a Mac
/// (install.sh, Debug) has none, so a release never replaces it. Only
/// Lostty's own GitHub feed counts: never Ghostty's.
enum UpdateFeed {
    static let infoKey = "LosttyUpdateFeed"
    static let prefix = "https://github.com/Lawliang/lostty/"

    static func url(info: [String: Any]?) -> String? {
        guard let feed = info?[infoKey] as? String, feed.hasPrefix(prefix),
              URL(string: feed) != nil else { return nil }
        return feed
    }

    static var current: String? { url(info: Bundle.main.infoDictionary) }
}
```

- [ ] **Step 4: The Info.plist key and the delegate**

In `macos/Lostty-Info.plist`, right after

```xml
	<key>SUPublicEDKey</key>
	<string>wsNcGf5hirwtdXMVnYoxRIX/SqZQLMOsYlD3q3imeok=</string>
```

add

```xml
	<key>LosttyUpdateFeed</key>
	<string>$(LOSTTY_UPDATE_FEED)</string>
```

In `UpdateDelegate.swift`, replace `feedURLString(for:)` (the comment and `return nil`) with:

```swift
    func feedURLString(for updater: SPUUpdater) -> String? {
        // Lostty's own feed, in release builds only (UpdateFeed). Never
        // upstream Ghostty's: with no `SUFeedURL` in Lostty-Info.plist, nil
        // leaves Sparkle with no feed at all.
        UpdateFeed.current
    }
```

- [ ] **Step 5: Run the tests**

Run: `macos/skins-test.sh UpdateFeedTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Check that the URL survives Info.plist preprocessing**

Run:

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -project macos/Lostty.xcodeproj \
  -scheme Lostty -configuration Debug SYMROOT="$PWD/macos/build" \
  LOSTTY_UPDATE_FEED=https://github.com/Lawliang/lostty/releases/latest/download/appcast.xml \
  build > macos/build/feed-check.log 2>&1; tail -1 macos/build/feed-check.log
/usr/libexec/PlistBuddy -c "Print :LosttyUpdateFeed" macos/build/Debug/Lostty.app/Contents/Info.plist
```

Expected: `** BUILD SUCCEEDED **`, then the whole URL. If it prints `https:`, the preprocessor cut the URL at `//`. In that case, rule and change the key to a flag (`LosttyUpdates` = `$(LOSTTY_UPDATES)`, `YES` only from `release.sh`), with the URL as a constant in `UpdateFeed`, and adjust the tests to match.

Then rebuild without the setting, so the Debug app goes back to having no feed:

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -project macos/Lostty.xcodeproj \
  -scheme Lostty -configuration Debug SYMROOT="$PWD/macos/build" build > macos/build/feed-check.log 2>&1
/usr/libexec/PlistBuddy -c "Print :LosttyUpdateFeed" macos/build/Debug/Lostty.app/Contents/Info.plist
```

Expected: an empty line.

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/Update/UpdateFeed.swift macos/Tests/Update/UpdateFeedTests.swift \
  macos/Lostty-Info.plist macos/Sources/Features/Update/UpdateDelegate.swift
git commit -m "lostty: update: read the feed only from release builds

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Daily checks that ask first; Check for Updates… on a local build

**Files:**
- Modify: `macos/Sources/Features/Update/UpdateFeed.swift`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (the update sync at ~914-934, `checkForUpdates(_:)` at ~1094, `validateMenuItem`'s `checkForUpdates` case at ~1511)
- Modify: `macos/Sources/Features/Update/UpdateController.swift` (`checkForUpdates`, `validateMenuItem`)
- Modify: `macos/Sources/Features/Update/UpdateViewModel.swift` (`extractSemanticVersion`)
- Modify: `macos/Lostty-Info.plist`
- Test: `macos/Tests/Update/UpdateFeedTests.swift`, `macos/Tests/Update/ReleaseNotesTests.swift`

Rulings:
- `AppDelegate.validateMenuItem` returns `false` for Check for Updates… today, so the menu item is always disabled. Without a change, the spec's message could never show. It now asks `updateController.canCheck`.
- Release notes only link for `x.y.z` versions. Lostty's are `X.Y`, so the pattern also accepts `X.Y`, and "View Release Notes" opens `releases/tag/vX.Y`.

**Interfaces:**
- Consumes: `UpdateFeed.current` (Task 2), `Ghostty.Config.AutoUpdate` (`off`/`check`/`download`).
- Produces:
  - `struct UpdateFeed.Schedule: Equatable { var checks: Bool; var downloads: Bool }`
  - `static func schedule(hasFeed: Bool, autoUpdate: Ghostty.Config.AutoUpdate?) -> Schedule`
  - `enum UpdateFeed.CheckAction { case sparkle, explainLocalBuild }`
  - `static func checkAction(feed: String?) -> CheckAction`
  - `static let localBuildMessage: String`
  - `UpdateController.canCheck: Bool`

- [ ] **Step 1: Write the failing tests**

Add to `UpdateFeedTests` (before its closing brace):

```swift
    @Test func noFeedNeverChecks() {
        for setting: Ghostty.Config.AutoUpdate? in [nil, .off, .check, .download] {
            #expect(UpdateFeed.schedule(hasFeed: false, autoUpdate: setting)
                == UpdateFeed.Schedule(checks: false, downloads: false))
        }
    }

    @Test func aFeedChecksAndAsksFirst() {
        #expect(UpdateFeed.schedule(hasFeed: true, autoUpdate: nil) == UpdateFeed.Schedule(checks: true, downloads: false))
        #expect(UpdateFeed.schedule(hasFeed: true, autoUpdate: .check) == UpdateFeed.Schedule(checks: true, downloads: false))
    }

    @Test func theAutoUpdateSettingStillWins() {
        #expect(UpdateFeed.schedule(hasFeed: true, autoUpdate: .off) == UpdateFeed.Schedule(checks: false, downloads: false))
        #expect(UpdateFeed.schedule(hasFeed: true, autoUpdate: .download) == UpdateFeed.Schedule(checks: true, downloads: true))
    }

    @Test func checkingOnALocalBuildExplainsWhy() {
        #expect(UpdateFeed.checkAction(feed: nil) == .explainLocalBuild)
        #expect(UpdateFeed.checkAction(feed: Self.feed) == .sparkle)
        #expect(UpdateFeed.localBuildMessage == "This copy of Lostty was built on this Mac; it updates with install.sh.")
    }

    @Test func theAppChecksDaily() {
        let info = Bundle(for: UpdateController.self).infoDictionary
        #expect(info?["SUScheduledCheckInterval"] as? Int == 86400)
        #expect(info?["SUEnableAutomaticChecks"] == nil)
    }
```

Add `import Foundation` under `import Testing` in that file. Add to `ReleaseNotesTests` (before its closing brace):

```swift
    @Test func aLosttyReleaseLinksItsTag() {
        let notes = UpdateState.ReleaseNotes(displayVersionString: "0.2", currentCommit: nil)
        #expect(notes?.url.absoluteString == "https://github.com/Lawliang/lostty/releases/tag/v0.2")
        #expect(notes?.label == "View Release Notes")
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `macos/skins-test.sh UpdateFeedTests; macos/skins-test.sh ReleaseNotesTests`
Expected: the test target fails to compile (`UpdateFeed` has no member `schedule`); `aLosttyReleaseLinksItsTag` runs once it compiles and fails until Step 5's pattern change (check it after Step 3).

- [ ] **Step 3: The decisions, in `UpdateFeed`**

Add inside `enum UpdateFeed`:

```swift
    /// Shown by Check for Updates… in a copy with no feed.
    static let localBuildMessage = "This copy of Lostty was built on this Mac; it updates with install.sh."

    struct Schedule: Equatable {
        var checks: Bool
        var downloads: Bool
    }

    /// No feed: never check. A feed: check daily and ask first, unless the
    /// `auto-update` config says otherwise.
    static func schedule(hasFeed: Bool, autoUpdate: Ghostty.Config.AutoUpdate?) -> Schedule {
        guard hasFeed else { return Schedule(checks: false, downloads: false) }
        switch autoUpdate {
        case .off: return Schedule(checks: false, downloads: false)
        case .download: return Schedule(checks: true, downloads: true)
        case .check, nil: return Schedule(checks: true, downloads: false)
        }
    }

    enum CheckAction: Equatable {
        case sparkle
        case explainLocalBuild
    }

    static func checkAction(feed: String?) -> CheckAction {
        feed == nil ? .explainLocalBuild : .sparkle
    }
```

- [ ] **Step 4: The Info.plist**

In `macos/Lostty-Info.plist`, delete

```xml
	<key>SUEnableAutomaticChecks</key>
	<false/>
```

and add, after the `LosttyUpdateFeed` string,

```xml
	<key>SUScheduledCheckInterval</key>
	<integer>86400</integer>
```

- [ ] **Step 5: Wire it up**

In `AppDelegate.swift`, replace the whole update sync, from the `// Sync our auto-update settings.` comment through the `else if let autoUpdate` block's closing brace (including its `/* To test … */` comment), with:

```swift
        // Lostty's updates: release builds check daily and ask first; a build
        // made on this Mac never checks (UpdateFeed). Setting both every time
        // also means Sparkle never asks "check automatically?".
        let schedule = UpdateFeed.schedule(hasFeed: UpdateFeed.current != nil, autoUpdate: config.autoUpdate)
        updateController.updater.automaticallyChecksForUpdates = schedule.checks
        updateController.updater.automaticallyDownloadsUpdates = schedule.downloads
```

In `AppDelegate.validateMenuItem`, replace the `checkForUpdates(_:)` case's comment and `return false` with:

```swift
        case #selector(checkForUpdates(_:)):
            return updateController.canCheck
```

In `UpdateController.swift`, put this at the top of `checkForUpdates()`, before `// If we're already idle`:

```swift
        if UpdateFeed.checkAction(feed: UpdateFeed.current) == .explainLocalBuild {
            let alert = NSAlert()
            alert.messageText = "No updates to check for"
            alert.informativeText = UpdateFeed.localBuildMessage
            alert.runModal()
            return
        }
```

Then replace `validateMenuItem(_:)` with:

```swift
    /// Whether Check for Updates… can run: always in a build made on this
    /// Mac (it explains how that build updates), else when Sparkle can.
    var canCheck: Bool {
        UpdateFeed.current == nil || updater.canCheckForUpdates
    }

    /// Validate the check for updates menu item.
    ///
    /// - Parameter item: The menu item to validate
    /// - Returns: Whether the menu item should be enabled
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(checkForUpdates) {
            return canCheck
        }
        return true
    }
```

In `UpdateViewModel.swift`, in `extractSemanticVersion`, change the pattern to:

```swift
            let pattern = #"^\d+\.\d+(\.\d+)?$"#
```

- [ ] **Step 6: Run the tests**

Run: `macos/skins-test.sh UpdateFeedTests && macos/skins-test.sh ReleaseNotesTests && macos/skins-test.sh UpdateStateTests && macos/skins-test.sh UpdateViewModelTests`
Expected: four `** TEST SUCCEEDED **`.

Then the whole suite: `macos/skins-test.sh > macos/build/suite.log 2>&1; tail -3 macos/build/suite.log`
Expected: `** TEST SUCCEEDED **`. `BranchSummarizerTests/cancelKillsTheRun` has been flaky under full-suite load. If it alone fails, rerun that suite three times and report both results.

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/Update/UpdateFeed.swift macos/Tests/Update/UpdateFeedTests.swift \
  macos/Tests/Update/ReleaseNotesTests.swift macos/Lostty-Info.plist macos/Sources/App/macOS/AppDelegate.swift \
  macos/Sources/Features/Update/UpdateController.swift macos/Sources/Features/Update/UpdateViewModel.swift
git commit -m "lostty: update: release builds check daily and ask first

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `macos/release.sh`

**Files:**
- Create: `macos/release.sh`

Rulings:
- Spec §4.1 says "on `main`". The owner works on `skins` and pushes `skins:main`, with no local `main`, so the check is: `HEAD` equals `origin/main` after a fetch, on any branch.
- Sparkle's tools come from the release's own DerivedData (`macos/build/release/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin`), resolved with `-resolvePackageDependencies` when missing.
- `--make-key` edits the plist line with `sed`. PlistBuddy would rewrite the whole preprocessed file.

**Interfaces:**
- Consumes: `macos/release_helper.py` CLI (Task 1); the Info.plist build setting `LOSTTY_UPDATE_FEED` (Task 2).
- Produces: `macos/release.sh [--version X.Y] [--dry-run]`, `macos/release.sh --make-key`; outputs in `macos/build/release/` (`Lostty.dmg`, `appcast.xml`, `notes.md`, logs).

- [ ] **Step 1: Check the `gh` call it relies on**

Run: `gh release list --repo Lawliang/lostty --limit 1 --exclude-drafts --json tagName --jq '.[0].tagName // ""'`
Expected: an empty line (no releases yet). If `--json` is unknown, `gh` is too old: `brew upgrade gh`.

- [ ] **Step 2: Write the script**

`macos/release.sh` (then `chmod +x macos/release.sh`):

```sh
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
```

- [ ] **Step 3: Check what can run without the certificate**

Run: `sh -n macos/release.sh && echo syntax-ok && macos/release.sh --nope; echo "exit $?"`
Expected: `syntax-ok`, the usage line, `exit 2`.

Run: `macos/release.sh --dry-run; echo "exit $?"`
Expected: `==> Checking`, then the first precondition that fails here, and `exit 1`. Before this plan's commits reach GitHub, that's `release: this commit isn't GitHub's main…`. With a dirty tree it's `release: commit or stash your changes first.` Nothing gets built.

Run the certificate check by itself, the same way the script does: `security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*(K85Z63QH48)\)".*/\1/p' | head -1`
Expected: an empty line today (there's no Developer ID certificate yet), so the script would stop with the "no Developer ID Application certificate…" message.

Everything from the build onward needs the Developer ID certificate, the notary login and the key, so it first runs in Task 6. Say so in the task report.

- [ ] **Step 4: Commit**

```bash
git add macos/release.sh
git commit -m "lostty: release: build, notarize and publish Lostty.dmg with its update feed

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The README download step; build-from-source and release docs

**Files:**
- Modify: `macos/setup.sh` (`--tools-only`)
- Modify: `README.md` (Getting Started)
- Modify: `CONTRIBUTING.md` (Develop Lostty)

Ruling: the iPhone steps still need the repo and its tools, which `setup.sh` installs. A user with the downloaded Mac app shouldn't build the Mac app too, so `setup.sh --tools-only` stops before `install.sh`.

- [ ] **Step 1: `setup.sh --tools-only`**

In `macos/setup.sh`:
- Add this line to the header comment, after `# missing, and runs install.sh. Safe to run again.`:

  ```sh
  #   --tools-only: just the tools (for the iPhone app, with Lostty for Mac downloaded)
  ```
- Replace the closing lines

  ```sh
  macos/install.sh
  if ! pgrep -xf /Applications/Lostty.app/Contents/MacOS/lostty >/dev/null; then
  ```

  with

  ```sh
  if [ "${1:-}" = "--tools-only" ]; then
    echo "The tools are ready. For the iPhone app: macos/install-phone.sh"
    exit 0
  fi
  macos/install.sh
  if ! pgrep -xf /Applications/Lostty.app/Contents/MacOS/lostty >/dev/null; then
  ```

Run: `sh -n macos/setup.sh && macos/setup.sh --tools-only`
Expected: `The tools are ready. For the iPhone app: macos/install-phone.sh`, with no build. Everything is already installed on this Mac.

- [ ] **Step 2: README Getting Started**

Replace everything from `## Getting Started` up to (not including) `### Pair them` with:

````markdown
## Getting Started

**You'll need:** a Mac on macOS 14 or later, and an iPhone on iOS 17 or later with its cable. The iPhone app also needs Xcode 26 (macOS 15 or later) and a free [Apple Account](https://account.apple.com).

### On your Mac

<details>
<summary><strong>1. Download Lostty</strong></summary>

[Download Lostty](https://github.com/Lawliang/lostty/releases/latest/download/Lostty.dmg), open it, and drag **Lostty** to **Applications**. Then open Lostty from Applications.

Lostty checks for updates once a day and asks before installing one. Installing an update keeps your terminals.

</details>

### On your iPhone

<details>
<summary><strong>2. Install Xcode 26 and sign in</strong></summary>

Get Xcode from the [App Store](https://apps.apple.com/app/xcode/id497799835) and open it once. Then **Xcode → Settings → Accounts**, click **+**, and sign in with your Apple Account. You'll also need [Homebrew](https://brew.sh).

</details>

<details>
<summary><strong>3. Install the app</strong></summary>

Plug your iPhone into the Mac, unlock it, and tap **Trust**. Then, in Terminal:

```sh
git clone https://github.com/Lawliang/lostty.git
cd lostty
macos/setup.sh --tools-only
macos/install-phone.sh
```

The first time, the phone may ask you to:

- turn on **Settings → Privacy & Security → Developer Mode** (the phone restarts);
- trust your Apple Account in **Settings → General → VPN & Device Management**.

Then run `macos/install-phone.sh` again.

**With a free Apple Account,** the app stops opening after 7 days. Run `macos/install-phone.sh` again to renew it. A paid developer account makes it last a year.

</details>

````

Then renumber the pairing steps:

```bash
sed -i '' -e 's|<strong>5. Install Tailscale on both</strong>|<strong>4. Install Tailscale on both</strong>|' \
  -e 's|<strong>6. Pair</strong>|<strong>5. Pair</strong>|' README.md
grep -n "<summary>" README.md
```

Expected: summaries `1. Download Lostty` through `5. Pair`, in order, with no number repeated.

- [ ] **Step 3: CONTRIBUTING.md**

Insert right after the `## Develop Lostty` heading's line `How to build, test and debug Lostty.`, before `### Prerequisites`:

````markdown
### Build from source

To build Lostty from this repo instead of downloading it:

```sh
git clone https://github.com/Lawliang/lostty.git
cd lostty
macos/setup.sh
```

`setup.sh` installs the prerequisites below, then builds Lostty into `/Applications`. A copy built this way never checks for updates. To update it, `git pull`, run `macos/install.sh`, then choose **Restart to Update** in Lostty's menu bar. Don't Quit Lostty to update: quitting ends every terminal session.

````

Append at the end of the file:

````markdown
### Release

Releases are made on the owner's Mac with `macos/release.sh`. It builds Lostty, signs it as Developer ID, has Apple notarize `Lostty.dmg`, and publishes it with Sparkle's `appcast.xml` as a GitHub release. Installed copies find it through that feed.

One-time setup, for team K85Z63QH48:

1. **Developer ID Application certificate:** Xcode → Settings → Accounts → Manage Certificates → **+** → Developer ID Application. Only the Account Holder can make it.
2. **Notarization login:** make an app-specific password at [account.apple.com](https://account.apple.com), then run `xcrun notarytool store-credentials lostty-notary --apple-id <your Apple ID> --team-id K85Z63QH48`.
3. **Update-signing key:** `macos/release.sh --make-key` puts the key in your login keychain and its public half in `macos/Lostty-Info.plist`. Commit that and push it to main.

Then, from a clean checkout of GitHub's `main`:

```sh
macos/release.sh --dry-run   # everything but publishing
macos/release.sh             # 0.2, 0.3, …; --version 1.0 to jump
```

It opens the release notes in `$EDITOR` first; an empty file stops it.
````

- [ ] **Step 4: Check and commit**

Run: `grep -n "Lostty.dmg\|tools-only" README.md && grep -n "^### " CONTRIBUTING.md`
Expected: the download link and `setup.sh --tools-only` in the README. CONTRIBUTING's `###` list starts with `Build from source`, `Prerequisites`, … and ends with `Release`.

```bash
git add macos/setup.sh README.md CONTRIBUTING.md
git commit -m "lostty: README: download Lostty for Mac; build-from-source and release docs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Don't push: the README's download link doesn't work until the first release (Task 6).

---

### Task 6: Owner setup, dry run, first release (owner-gated)

Every step here needs the owner, or something only the owner can create. None of it is code. Stop at each gate.

- [ ] **Step 1: Walk the owner through the one-time setup** (CONTRIBUTING.md → Release, items 1 and 2). They create the Developer ID Application certificate and run `xcrun notarytool store-credentials lostty-notary …` themselves (it asks for their password).

Check: `security find-identity -v -p codesigning | grep -c "Developer ID Application: .*(K85Z63QH48)"` → `1`; `xcrun notarytool history --keychain-profile lostty-notary > /dev/null && echo ok` → `ok`.

- [ ] **Step 2: The update-signing key**

Run: `macos/release.sh --make-key`
Expected: `Put the update-signing key … in macos/Lostty-Info.plist. …`, and `git diff macos/Lostty-Info.plist` shows only the `SUPublicEDKey` string changing.

```bash
git add macos/Lostty-Info.plist
git commit -m "lostty: release: Lostty's own update-signing key

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Ask the owner before pushing. Releases need `HEAD` to equal GitHub's `main`, so the branch has to go to `main`: `GIT_NO_REPLACE_OBJECTS=1 git push origin HEAD:main HEAD:skins`. The README's download link only goes live with the first release, so push Task 5 to `main` just before releasing, not earlier.

- [ ] **Step 3: Dry run**

Run: `EDITOR=true macos/release.sh --dry-run`
Expected: every step through `==> Writing the update feed`, then `Dry run: …/Lostty.dmg and …/appcast.xml are ready. Nothing was published.`

Then check:
- `xcrun stapler validate macos/build/release/Lostty.dmg` → `The validate action worked!`
- `cat macos/build/release/spctl-app.log` → `accepted` with `source=Notarized Developer ID`
- `python3 -I -c 'import xml.etree.ElementTree as E,sys; E.parse(sys.argv[1]); print("feed ok")' macos/build/release/appcast.xml` → `feed ok`

Ruling (spec §8 says to open the app from the DMG on this Mac): don't. A second Lostty with the same bundle ID would join the owner's running one and its sessions. The `spctl` acceptance of the app inside the stapled DMG is the Gatekeeper check. If a failure needs `syspolicy_check distribution <app>`, it can run without opening the app.

If the archive or export fails on signing (for example the dock-tile plugin's manual signing, or Sparkle's helpers), fix it in `release.sh` with a test-free ruling, because these steps need the real certificate. Rerun the dry run, then commit.

- [ ] **Step 4: First release, only when the owner says "release"**

Run: `macos/release.sh` (the owner edits the notes in their editor)
Expected: `Released Lostty 0.2: https://github.com/Lawliang/lostty/releases/tag/v0.2`. Then `curl -sIL https://github.com/Lawliang/lostty/releases/latest/download/Lostty.dmg | grep -i "^HTTP" | tail -1` → `HTTP/2 200`.

- [ ] **Step 5: Hand check for the owner, after 0.3**

On a second Mac or a guest account: install 0.2 from the README link, open some terminals, release 0.3, then Check for Updates… → Install. Lostty should restart on 0.3 with the terminals still there. This is the owner's check. Record the result in the ledger.
