# Lostty Beta — design

Date: 2026-10-15. Status: approved in conversation; this spec awaits review.

## 1. Goal

Stable Lostty, the build people download, leaves out what isn't finished.
Lostty Beta is the same `main` with those features on. Today that means the
clickable mascot and Branches. The owner runs the beta, and anyone who wants
it can download it and get beta updates.

Out of scope: the iPhone app (unchanged; it has no mascot bubble and no
Branches panel), a website download link (the website has no download button
yet), and a "switch channel" setting inside the app.

## 2. Decisions (from the owner)

- **Beta only:** the mascot and Branches.
- **Both versions:** the sidebar and Skins.
- **No version:** the "+" (Add extension) button. It only says "More
  extensions are on the way."
- **One `main`, two builds.** Nothing lives only on a branch.
- **The beta replaces stable on a Mac; it doesn't run beside it.** Same
  bundle ID (`com.lawliang.lostty`), same file name (`/Applications/Lostty.app`),
  settings, terminals and phone pairing. The two would otherwise share a tmux
  server and fight over the same terminals. The beta shows as "Lostty Beta",
  with a "BETA" band on its icon.
- **The beta is published**, with its own download and its own update feed.
  Each build follows only its own feed. To switch, you download the other
  one; to go back to stable, you download stable.
- **Every stable release also publishes a matching beta** from the same
  commit, so the beta never misses a stable fix. `release.sh --beta`
  publishes a beta by itself in between.
- **Off means off.** In stable, a beta-only feature does no work: no turn
  summaries (which run Claude and spend tokens), no git watching for Branches.

## 3. The channel

`LosttyChannel` (`beta` or `stable`) goes in `Lostty-Info.plist` as
`$(LOSTTY_CHANNEL)`.
- **Empty means stable:** a release that forgets the flag ships the
  finished build.
- **Debug sets `beta`** in the project, so builds run from Xcode show
  everything.
- **ReleaseLocal and Release** leave it empty. `install.sh` and `release.sh`
  pass it on the `xcodebuild` command line, the way `release.sh` already
  passes `LOSTTY_UPDATE_FEED`.
- **It can't be flipped on a stable copy:** the plist is inside the signed
  app, so editing it breaks the signature.

`LosttyChannel.current` reads the key once. It is a small Swift type with
`isBeta` and the beta-only features as named checks (`showsMascot`,
`hasBranches`), so a call site says what it gates, not which channel it's in.
The pure parts take the Info.plist dictionary as input so tests cover both
values.

A beta build also passes:
- `INFOPLIST_KEY_CFBundleDisplayName="Lostty Beta"`: the menu bar, Dock,
  About and Sparkle's prompts show it.
- `ASSETCATALOG_COMPILER_APPICON_NAME=LosttyMacBetaIcon`: a second icon set,
  made once from `LosttyMacIcon` with a band across the bottom reading "BETA"
  in Lostty's accent color. It is rendered and shown to the owner before it is
  committed.

## 4. Gating (Mac app)

- **Mascot:**
  - `ExtensionSidebarLayout` adds the `SidebarMascot` overlay only when
    `showsMascot`.
  - `AppDelegate` connects `ClaudeRuntime`'s turn end to `TurnObserver` and
    calls `TurnObserver.shared.start()` only when `showsMascot`.
  - Settings → Mascot ("Summarize turns in the background") is hidden in
    stable.
  - `LosttyRestart` carries and restores transcripts only when the observer
    runs. A handoff from a beta build that a stable build reads ignores them.
- **Branches:**
  - The sidebar lists `LosttyExtension.available`, which is `allCases` minus
    `.branches` in stable. That is the only way to open it; no menu,
    shortcut, App Intent or restart state refers to it.
  - `ExtensionSidebarModel` starts branch watching only when Branches is
    available.
- **"+" button:** `AddExtensionIcon`, its button and the "More extensions
  are on the way." popover are deleted outright, not gated.
- **Settings that outlive a switch:** `LosttyObserverBackground` stays in
  UserDefaults. Stable ignores it, and the beta picks it up again.

## 5. Installing on the owner's Mac

- `install.sh` builds the **beta** by default: the owner develops the beta
  features, and other sessions that run plain `install.sh` must not take them
  away.
- `install.sh --stable` builds stable, to check what users get.
- Both install to `/Applications/Lostty.app`, through the existing
  previous-build swap, so Restart to Update and "Go Back to Previous Build"
  work unchanged.
- `--previous` is unchanged.

## 6. Releasing (`macos/release.sh`, `macos/release_helper.py`)

### Versions and tags
- Stable stays `0.2`, `0.3`, … with tag `vX.Y`.
- Betas are named after the stable release they build on:
  - `0.4 beta 1` is published with 0.4; then `0.4 beta 2`, `0.4 beta 3`
    between releases. When 0.5 ships, its matching beta is `0.5 beta 1`.
  - Tags are `vX.Y-beta.N`.
  - `MARKETING_VERSION` stays `X.Y`: Apple expects
    `CFBundleShortVersionString` to be plain numbers.
  - The beta number goes in a `LosttyBetaNumber` Info.plist key, from the
    `LOSTTY_BETA_NUMBER` build setting. Where Lostty shows its version (the
    About window), a beta build shows "Lostty Beta 0.4 beta 2".
  - Sparkle's `shortVersionString` and the release title say "0.4 beta 2".
- `next_version` (the next stable version) skips beta tags. It reads the
  newest release of any kind today.
- The next beta number is one more than the highest `vX.Y-beta.N` for the
  latest stable `X.Y`, or 1 if there are none.
- Build numbers stay `yyyymmddHHMM`, so update ordering holds across both
  channels.

### Feed and downloads
- Stable is unchanged: `releases/latest/download/appcast.xml`. GitHub's
  "latest" never includes pre-releases, so stable copies never see a beta.
- Each beta is a GitHub **pre-release** `vX.Y-beta.N` carrying
  `Lostty-Beta.dmg`.
- A fixed pre-release tagged **`beta`** holds the current `appcast-beta.xml`
  and `Lostty-Beta.dmg`, replaced on every beta release
  (`gh release upload beta --clobber`). Beta builds read
  `https://github.com/Lawliang/lostty/releases/download/beta/appcast-beta.xml`,
  which passes `UpdateFeed`'s `github.com/Lawliang/lostty/` prefix check.
- The appcast item points its enclosure at the versioned pre-release's DMG,
  so an update already offered keeps working after the next beta replaces the
  `beta` release's copy.
- The beta's download link is the `beta` release page. It always shows the
  newest beta.

### Release notes
- The matching beta reuses the stable release's notes.
- A beta published by itself lists the commits since the last release of
  either kind (skipping `docs:` commits as now), opened in `$EDITOR`.

### `release.sh` (stable)
1. Preconditions as now.
2. Build, sign, notarize and staple **both**:
   - stable with `LOSTTY_CHANNEL` empty and the stable feed
   - the matching beta with `LOSTTY_CHANNEL=beta`, the beta name and icon,
     and the beta feed
3. Publish stable (tag `vX.Y`, release, verify the feed) exactly as today.
4. Publish the matching beta (`vX.Y-beta.1` pre-release, then refresh the
   `beta` release, then verify the beta feed).
5. If the beta fails after stable is out, stable stays out. The script says
   what failed and that `release.sh --beta` finishes the job.

### `release.sh --beta`
Does steps 1, the beta half of 2, and 4. Its preconditions are the same as
stable's: on `main`, clean, equal to `origin/main`. `--dry-run` works with
both and prints where each DMG and feed would go.

## 7. Errors

- **Unknown `LosttyChannel` value:** treated as stable.
- **Beta feed unreachable or empty** (before the first beta): Sparkle's
  normal "no update" or error, the same as stable's before its first release.
- **`release.sh --beta` before any stable release exists:** stops with "Make
  a stable release first: betas are numbered after it."

## 8. Testing

- **Unit tests (Mac test target):**
  - `LosttyChannel`: empty, `beta`, `stable` and unknown values
  - `LosttyExtension.available` for each channel
  - stable never shows the mascot or starts the observer
  - the handoff ignores transcripts when the observer is off
- **`release_helper_test.py`:**
  - `next_version` ignores beta tags
  - next beta number: none yet, existing betas, a new stable resets it to 1
  - the beta appcast: title, the enclosure URL to the versioned DMG,
    `shortVersionString` `X.Y beta N`
  - notes for a beta published by itself span both kinds of tag
- **Builds:**
  - `install.sh --stable` and `install.sh` each build
  - the installed app's Info.plist shows the right channel, name and icon
  - stable has no mascot, no Branches icon and no "+" button
  - the beta has the mascot and Branches and no "+" button
- **Dry run** of `release.sh` and `release.sh --beta` before the first real
  beta release.

## 9. Docs

`CONTRIBUTING.md` gains a short "Stable and beta" section: what the channel
gates, how to gate a new feature (`LosttyChannel`), and the `install.sh` and
`release.sh` flags. The README doesn't change until there's a download link.
