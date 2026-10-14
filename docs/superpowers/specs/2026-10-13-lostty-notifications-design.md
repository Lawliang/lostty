# Lostty notifications — design

Status: draft for review (2026-10-13)

Builds on docs/superpowers/specs/2026-10-12-lostty-phone-session-list-design.md
(the phone's session list and its watch over SSH) and
docs/superpowers/specs/2026-10-12-lostty-menu-bar-stay-awake-design.md, which
left phone push as "a later spec" behind the `PhoneNotifier` stub. This is
that spec.

## Goal

The phone tells you when something needs you: a terminal waiting on you, or a
new phone build ready to install. Each note looks like the terminal it came
from. The bell (🔔) button at the right of the session list's top bar opens an inbox and carries
an unread badge. Settings → Notifications chooses, per kind of note, whether
it is off, only in the app, or also pushed to the phone.

### Success criteria

- Claude asks for permission in a terminal while the phone app is closed;
  opening the app shows a badge on the bell, and the inbox row for that terminal is
  in the terminal's colors with Claude's question.
- Answering that terminal, on the phone or at the Mac, clears its note.
- Publishing a build over Tailscale, with `macos/ship-phone.sh` for Lostty
  or the install-ios-build skill's `ship-ios.sh` for any other app, adds an
  install note in the colors of the terminal that ran it; tapping it brings
  up iOS's install prompt. A Lostty note is read once the phone runs that
  build. A build that went on over the cable adds no note.
- Stage 2: with Waiting on You set to Notify + Push to iOS, the phone in a pocket on
  LTE, app closed, gets a push within a few seconds of Claude asking; the
  app icon shows the unread count.
- No push while you're looking at that terminal on the phone, or while you've
  used the Mac's keyboard or mouse in the last 2 minutes. The inbox still
  gets the note.

## Facts this design rests on

- The phone hears about sessions only while it's open: one SSH connection
  runs `tmux -L lostty wait-for lostty-changed` in a loop and re-lists on
  each signal (`TmuxRemote.watchCommand`, `MobileStore.watchLoop`). Going to
  the background closes it (`MobileStore.scenePhaseChanged`).
- The Mac sets `@lostty_claude` (waiting/working/agents) and `@lostty_skin` on
  each tmux session (`ClaudeTmuxSync`, `TmuxOptionSync`) and knows which
  sessions a phone is attached to (`AttachedPhones`).
- The phone's SSH key is `restrict,pty … lostty-phone:<id>`: it can run
  commands, so it can read and write small files on the Mac.
- The iOS app has no push entitlement, background modes or notification code.
  The Apple team (K85Z63QH48) is paid; the phone build's profile is the
  wildcard `K85Z63QH48.*`, which can't carry push.
- `ship-phone.sh` (through `ship-phone-page.py`) writes `latest.json` (build,
  commit, manifest URL) that nothing reads yet, and stamps the app's
  `CFBundleVersion` with the build. It already reads the shipping terminal's
  title from `$TMUX_PANE`. It publishes, then installs over the cable when
  `devicectl` reaches the phone.
- The install-ios-build skill (`~/.claude/skills/install-ios-build/`) ships
  Lostty with `ship-phone.sh` and any other app with `ship-ios.sh`: the
  cable first, else an install page at `https://<Mac>.<tailnet>.ts.net/<app>/`.
  It prints the link and tells no one else.

## Decisions

| | Decision |
|---|---|
| Install notes | Any app's build published over Tailscale: Lostty's (`ship-phone.sh`) and others' (`ship-ios.sh`, from the install-ios-build skill). Tagged with app, project, branch and the terminal that ran it. None when the build went on over the cable. |
| Source of truth | The Mac keeps the notes. The phone reads them when open; the Mac pushes through APNs for push-mode kinds. |
| Stages | 1: Mac notes, inbox, badge, settings (push shows "not set up yet"). 2: APNs. |
| Kinds (v1) | Waiting on You; New Build. |
| Settings | Per kind: Off / Notify (in-app only) / Notify + Push to iOS. Per phone: Off hides that kind on that phone (the Mac still keeps the note); the Mac reads the settings only to decide pushes. Defaults: Notify (in-app only). Until stage 2, Notify + Push to iOS isn't offered. iOS's permission prompt appears the first time a Push mode is chosen. |
| Repeat waiting | One waiting note per terminal. A new waiting episode revives it (unread again, new time and text) instead of adding another. Re-push only if that terminal's last push was 5+ minutes ago. |
| Waiting text | Terminal name, then Claude's question (the row's action line), or "Waiting on you" without one. Same in push. |
| Read | Tapping a note reads it and opens its terminal, or starts the build's install. A waiting note reads itself when its terminal stops waiting. A Lostty build note reads itself once the phone runs that build or newer; another app's build note is read when tapped (Lostty can't see other apps' versions). "Mark all read" in the inbox. Read state is shared by all paired phones. |
| No push when | That terminal is open on a phone, or the Mac had keyboard/mouse input in the last 2 minutes. The note is still kept. |
| Inbox | A sheet from the bell: newest first, swipe to delete (for every phone), Mark all read (the kinds this phone shows). Rows styled like the terminal's session row; read rows dimmed. |
| Keeping | Unread notes stay until read; read notes go after 7 days; at most 100 (oldest read first). |
| Push look | Plain iOS banners titled with the terminal's name; no notification content extension. App icon badge = unread count (stage 2). |

## Design

### The note (shared, `LosttyRemote`)

`LosttyNote` (Codable): `id` (UUID), `kind` (`.waiting`, `.build`), `created`
and `updated` dates, `read` (Bool), `title`, `body`, the source terminal
(`sessionID`, `sessionName`, `skin` as `@lostty_skin`'s encoded string
captured when the note was made), and for builds `app`, `bundleID`, `build`,
`branch`, `project`, `installURL`.

`NoteLog` holds the list and every rule above as plain functions, so both
sides use the same rules and tests cover them without a Mac or a phone:
`sync(sessions:now:)` (waiting notes from a session listing: add, revive,
read when the terminal stops waiting), `apply(_ drop:now:)` (a drop file:
build, read, read all, delete, installed), `prune(now:)`, `unreadCount`, and
in stage 2 `shouldPush(note, lastPush:, now:)`.

### Mac: the notes keeper (`Sources/Features/PhoneNotes/`)

(`Sources/Features/Notifications/` is the Mac's own desktop notifications.)

- **Where:** `~/Library/Application Support/Lostty/notifications/`.
  `notes.json` is the log, written atomically by the Mac app only.
  `inbox/` is a drop folder: anyone writes one small JSON file per message;
  the Mac app watches it (a `DispatchSource` on the folder), applies each
  file to the log, and deletes it.
- **Waiting notes:** `NotesKeeper` re-lists sessions on each
  `.losttySessionsChanged` (the same listing the phone reads, so it sees
  `@lostty_claude`, the question, the title and the skin) and calls
  `NoteLog.sync`. Only one Lostty process keeps notes: the one holding an
  exclusive lock on `notifications/.lock` (debug and release builds share the
  tmux server).
- **Build notes:** both ship scripts, once a build is published on its
  install page, drop `inbox/build-<app>-<build>.json` with app name, bundle
  id, build, commit, branch, project, the `itms-services` install URL, and the
  terminal that ran it: session id, title and `@lostty_skin`, read in one
  `tmux display-message -p -t "$TMUX_PANE"` (`ship-phone.sh` already reads the
  title there). Without `$TMUX_PANE` the note has no terminal and uses
  Lostty's own look. `ship-phone.sh` drops it only when its cable install
  didn't happen or failed; `ship-ios.sh` only on its Tailscale path. The
  drop is a few lines of shell writing JSON through `python3 -I`, as the
  scripts already do; when the folder doesn't exist (no Lostty on this Mac)
  they skip it.
- **From the phone:** `inbox/read-<uuid>.json` (note ids or "all"),
  `inbox/phone-<phone id>.json` (that phone's settings and, in stage 2, its
  device token), `inbox/installed-<phone id>.json` (the build it runs).
  Per-phone settings live in `phones.json` next to `notes.json`.
- **Telling the phone:** after each change to `notes.json`, the Mac signals
  `tmux -L lostty wait-for -S lostty-changed`, which the phone's watch already
  re-lists on.
- `PhoneNotifier` (the stub in `StayAwakeStore.swift`) becomes the push
  sender's protocol; stage 1 keeps `NoPhoneNotifier`.

### Phone (`Sources/App/iOS/`)

- **Reading:** the watch's re-list also runs `cat` of `notes.json` (one more
  command on the same connection) and publishes `notes` on `MobileStore`.
- **Writing:** small commands that write a file into `inbox/` (read marks,
  settings, installed build, device token). Nothing on the phone writes
  `notes.json`.
- **Bell button:** the existing placeholder in `SessionsScreen.swift` gets an
  action (open the inbox sheet) and a badge with `unreadCount`. This is the
  only change to that file besides making `RowColors` reachable (drop
  `private`) so inbox rows reuse it; the other terminal edits it too.
- **`NotificationsInbox.swift`:** the sheet. Rows use `RowColors(skin:)` and
  the texture tile like session rows. Tapping a waiting note opens its
  terminal through the same path a row tap uses; a build note opens its
  `itms-services` URL.
- **`NotificationSettingsScreen.swift`:** Settings → Notifications. One row
  per kind with Off / Notify (in-app only) / Notify + Push to iOS. Until
  stage 2, Notify + Push to iOS isn't offered.
- **Installed build:** on launch, if `CFBundleVersion` changed, write
  `installed-<phone id>.json`.

### Stage 2: push

- **Apple side (you, once):** create an APNs auth key (.p8) in the developer
  account; note its Key ID.
- **Mac:** Phone Access gets "Set Up Push": pick the .p8, enter the Key ID;
  the key goes to the Keychain. `APNsNotifier` implements `PhoneNotifier`:
  signs a JWT (ES256, CryptoKit `P256.Signing`), POSTs over HTTP/2 to
  `api.sandbox.push.apple.com` (development-signed builds) for each phone
  whose settings push that kind, with `aps.alert` and `aps.badge` =
  `unreadCount`. Skips when `AttachedPhones` shows that terminal attached, or
  `CGEventSource.secondsSinceLastEventType` < 120 s.
- **Phone:** a `Lostty-iOS.entitlements` with `aps-environment: development`
  (automatic signing makes an explicit App ID with push);
  `registerForRemoteNotifications` after permission; the token goes to the
  Mac in `phone-<id>.json`. Tapping a push opens the app on that note.
  `setBadgeCount` keeps the icon in step while the app is open.

## Errors

- A malformed drop file is logged and deleted, never applied in part.
- `notes.json` missing on the Mac: the phone shows no notes. Unreadable, or
  the read fails: the phone keeps the last notes it read; the session list
  is unaffected.
- A note whose terminal has ended: tapping it marks it read and says the
  terminal ended.
- APNs rejects a token (410/400 BadDeviceToken): drop that token; the phone
  sends a new one next launch.

## Testing

- `NoteLog` rules in `LosttyRemote` tests (`swift test`): refresh vs add,
  5-minute re-push, auto-read on stop and on install, pruning, cap, shared
  read across phones.
- Mac: the notes folder (load, save, drain the inbox) in `macos/Tests`.
- Ship scripts: run each once from a Lostty terminal with the phone
  unplugged and check the drop file (app, link, skin); once with the phone
  reachable and check there's none.
- Phone, on the simulator: inbox styling, badge, settings, tap-to-open,
  Mark all read.
- Stage 2 by hand on the iPhone: push with the app closed, idle skip,
  attached skip, icon badge.

## Out of scope

- Other kinds (Claude finished, terminal ended, Mac sleeping), per-project
  settings, a notification content extension.
- Telling a cable install apart in the inbox: a build that went on over the
  cable makes no note.
