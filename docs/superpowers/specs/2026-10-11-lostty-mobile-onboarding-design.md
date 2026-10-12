# Lostty Mobile onboarding — design

Status: draft for review (2026-10-11)

Builds on docs/superpowers/specs/2026-10-09-lostty-mobile-design.md, whose
phases 0–3 are built: Mac windows live in sessions on `tmux -L lostty`, and
the iPhone app attaches to them over SSH through Tailscale.

## Goal

A developer who has never seen Lostty goes from two installed apps to a
working phone session without typing an address, copying a key, editing a
file or running a command, and without Lostty weakening their Mac's security.
Lostty is open source and hosts nothing: customers bring their own Tailscale.

### Success criteria

- Setup on the Mac is one window with a checklist; every unmet item has a fix
  button, and the fixes need at most one admin password prompt.
- Pairing a phone is: click Pair a Phone on the Mac, scan the QR code with the
  phone, click Allow on the Mac. Nothing is typed on either device.
- Pairing only reports success after the phone has connected over Tailscale.
- After setup, the Mac accepts no SSH password logins (unless the customer
  explicitly skips that step), and phone keys cannot forward ports.
- Removing a phone, or turning Phone Access off, undoes what Lostty added.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Network | Customer's own Tailscale on both devices | Open source, nothing hosted; works across any networks |
| Who answers the phone on the Mac | macOS Remote Login (system sshd), hardened | Apple's sshd checks every login; Lostty writes no authentication code |
| Password logins | Turned off for all accounts by default; skippable with a warning | A password door on any account is a way in; some developers rely on password SSH |
| tmux | Homebrew, with a guided install | Homebrew owns tmux security updates |
| Pairing transport | Network framework, nearby only (Bonjour, peer-to-peer allowed), TLS with a pre-shared key from the QR | Multipeer Connectivity is deprecated in the 27 SDKs; works on Wi-Fi that isolates clients |
| Pairing confirmation | QR scan plus an Allow click on the Mac; no matching code | The QR authenticates the Mac to the phone; Allow stops a photographed QR |
| Mac identity on the phone | Pinned from the QR | No trust-on-first-use |
| Macs per phone | One; pairing again replaces it | Simplest phone UI; several phones per Mac still work |
| Terminfo | Copied into `~/.terminfo` | Survives moving or renaming Lostty.app; the phone needs no path |

## Architecture

```
Mac Lostty                                   iPhone Lostty
 Phone Access window                          Welcome → Pair with Mac
  checklist ──(one admin prompt)──▶ sshd       scanner (QR)
  Pair a Phone: QR + NWListener ◀── nearby ──▶ NWBrowser + NWConnection
   (TLS-PSK, 2 min, one key)                    sends public key
  Allow? → ~/.ssh/authorized_keys              test connection ──Tailscale──▶ sshd ──▶ tmux
```

Three parts:

1. **Mac: Phone Access** — checklist, admin setup, pairing listener,
   authorized_keys editing, paired-phones list.
2. **Phone: pairing and first run** — welcome screen, scanner, pairing client,
   test connection, pinned identity, errors.
3. **`LosttyRemote` (shared)** — QR payload, pre-shared key derivation,
   pairing messages; all platform-neutral and unit-tested.

## 1. Mac: Phone Access

A "Phone Access…" item in the Lostty app menu opens its own window.

### Checklist

Each row shows ✓, ⚠ or ✗ with a fix. The window re-checks when it opens,
when it becomes key, and after each fix.

| Row | Check (no admin) | Fix |
|---|---|---|
| Tailscale | `Tailscale status --json` from `/Applications/Tailscale.app/Contents/MacOS/`: `BackendState` is `Running`; read `Self.DNSName` and `Self.TailscaleIPs` | "Open Tailscale" |
| tmux | The paths `src/cli/tmux/session.zig` already searches | Shows `brew install tmux` with Copy, and a link to brew.sh |
| Remote Login | `launchctl print-disabled system` lists `"com.openssh.sshd" => enabled`, and 127.0.0.1:22 accepts a TCP connection | Admin setup (below) |
| Password logins off | `ssh -o BatchMode=yes -o PreferredAuthentications=none -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null <user>@127.0.0.1` fails with `Permission denied (publickey)`: the methods in parentheses are exactly `publickey` | Admin setup; or "Skip" → ⚠ with the warning below |
| Firewall | `/usr/libexec/ApplicationFirewall/socketfilterfw --getblockall` is not enabled | Opens System Settings → Network → Firewall |
| Terminfo | `~/.terminfo` holds the same `xterm-ghostty` entry as the bundle | Copies the bundle's terminfo tree into `~/.terminfo` (no admin) |

Below the rows: "Your phone can reach this Mac only while it's awake."

Skip warning: "Without this, anyone who can reach this Mac can try your
password over SSH, on any network, for every account on this Mac. If you SSH
into this Mac with a password from elsewhere, that keeps working."

### Admin setup

One `NSAppleScript` `do shell script … with administrator privileges` prompt
runs:

```sh
launchctl enable system/com.openssh.sshd
launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
# omitted when the customer skipped the lockdown:
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' \
  > /etc/ssh/sshd_config.d/000-lostty.conf
chmod 644 /etc/ssh/sshd_config.d/000-lostty.conf
```

- `systemsetup -setremotelogin` is not used: it needs Full Disk Access.
- `bootstrap` fails when sshd is already loaded; the checklist re-check, not
  the exit code, decides success.
- sshd is started per connection by launchd, so the file applies to the next
  connection with no restart. OpenSSH takes the first value it reads, and
  drop-ins are read in name order before the rest of `sshd_config`, so
  `000-` wins unless a customer file sorts earlier or a `Match` block
  overrides it. The "Password logins off" probe catches both.
- The prompt only appears when a row it fixes is unmet.

### Pair a Phone

Enabled when every row is ✓ or ⚠. Opens a sheet with the QR code and
"Scan this with Lostty on your iPhone."

- **QR payload** (`PairingPayload`): `lostty://pair?v=1&name=<MagicDNS
  name>&ip=<Tailscale IPv4>&user=<short user name>&hostkey=<base64 of
  /etc/ssh/ssh_host_ed25519_key.pub's key>&secret=<base64url, 32 random
  bytes>`.
- **Listener**: `NWListener` advertising Bonjour service `_lostty-pair._tcp`
  named with the first 8 hex digits of SHA-256(secret), with
  `includePeerToPeer = true`, using TLS with a pre-shared key: key =
  HKDF-SHA256(secret, info `lostty-pair-v1`), identity `lostty-pair`.
- The listener accepts one connection, closes after one request, on Cancel,
  or after two minutes (the sheet then says so and offers a new code). A new
  sheet always makes a new secret.
- **Request** (phone → Mac, JSON): `{"v":1,"publicKey":"ecdsa-sha2-nistp256
  AAAA… ","model":"iPhone 13"}`. The key must parse as an SSH public key of
  type `ecdsa-sha2-nistp256`; anything else is refused without a prompt.
- **Allow prompt**: "Allow “iPhone 13” to open your Lostty sessions?" Allow /
  Deny.
- **Response** (Mac → phone): `{"v":1,"result":"allowed"}` or `"denied"`.
- On Allow, append to `~/.ssh/authorized_keys` (created 0600, `~/.ssh` 0700 if
  missing):
  `restrict,pty <type> <base64> lostty-phone:<uuid>`. `restrict` blocks
  forwarding; `pty` re-allows the terminal. The phone's name and pairing
  date are stored in `UserDefaults.ghostty` under the uuid. A key already
  present is not added twice.

### Paired phones

Lists `authorized_keys` lines whose comment is `lostty-phone:<uuid>`, with
name and date. Rename edits the stored name. Remove deletes that line.

**Turn Off Phone Access** removes every `lostty-phone:` line, then offers one
admin prompt to delete `000-lostty.conf` (turning password logins back on).
Remote Login is left as it is. Docs cover the manual cleanup for people who
delete the app instead.

`authorized_keys` is rewritten atomically (write a temp file in `~/.ssh`,
keep permissions, rename), and lines Lostty did not add are never touched.

## 2. Phone: pairing and first run

### Welcome

Shown while no Mac is paired:

1. Install Tailscale on your Mac and this iPhone, signed into the same account.
2. On your Mac, open Lostty → Phone Access.
3. Tap **Pair with Mac**.

The existing address/user/port fields move under **Advanced** in Settings;
the terminfo field is removed. Section 1 copies terminfo to `~/.terminfo`,
where ncurses looks by default, so the attach line
(`TmuxRemote.attachCommand`) stops exporting `TERMINFO`.

### Pairing

1. **Scan** with VisionKit's `DataScannerViewController`; only `lostty://pair`
   payloads with `v=1` are accepted.
2. **Find** the Mac with `NWBrowser` for `_lostty-pair._tcp` (peer-to-peer
   allowed), matching the service name derived from the secret; connect with
   the same TLS pre-shared key.
3. **Send** the request with the phone's Secure Enclave public key (created
   if needed, as today) and a model name: the hardware identifier
   (`utsname.machine`, e.g. `iPhone14,5`) looked up in a short table of
   recent models ("iPhone 13"), falling back to "iPhone".
4. **Wait** for Allow. Denied → "Your Mac declined. Try again from Phone
   Access."
5. **Pin** the Mac's identity: store `hostkey` for both `name` and `ip` in
   `KnownHosts`, replacing any earlier entry. Connections to a paired Mac
   offer only `ssh-ed25519` as the host key algorithm, so sshd presents the
   key that was pinned.
6. **Test**: connect over Tailscale with the existing `RemoteConnection`
   (name first, then ip) and list sessions. Only success saves the pairing
   and opens the session list. Failure keeps the scanned payload and shows
   "Is Tailscale on and signed into the same account as your Mac?" with
   Retry.

`RemoteHostSettings` gains `fallbackHost` (the ip) and `paired` (true when
set by pairing). Pairing again replaces the Mac.

### Errors after pairing

| Situation | Phone shows |
|---|---|
| Host key differs from the pinned one | "This Mac's identity changed. If you reinstalled macOS, pair again; otherwise, don't connect." + Pair Again. Never re-trusts silently. |
| Name and ip both unreachable | "Can't reach your Mac. Is Tailscale on here and on the Mac, and is the Mac awake?" |
| Key refused | "Your Mac doesn't accept this phone anymore." + Pair Again |
| Connected, no sessions | "No sessions. Is Lostty open on your Mac?" |

Face ID behaves as today: once each time the app returns from the background.

## 3. `LosttyRemote` additions

- `PairingPayload`: encode/decode the `lostty://pair` URL; rejects unknown `v`,
  missing fields, bad base64, a non-ed25519 host key.
- `PairingCrypto`: service name and pre-shared key from the secret.
- `PairingMessage`: request/response JSON.
- `AuthorizedKeys` (macOS-only file, pure functions over text): add, list,
  remove `lostty-phone:` lines; leaves other lines byte-for-byte.

## Privacy keys and entitlements

- iOS: `NSCameraUsageDescription`, `NSLocalNetworkUsageDescription`,
  `NSBonjourServices` = `_lostty-pair._tcp`.
- macOS: `NSLocalNetworkUsageDescription` (macOS 15+) worded for Phone Access,
  `NSBonjourServices` = `_lostty-pair._tcp`.
- No new entitlements; the user-assigned device name entitlement is not
  requested.

## Testing

- Unit (`LosttyRemote`): payload round-trip and every rejection; service name
  and key derivation are stable; message codec; `AuthorizedKeys` add/list/
  remove/no-duplicate keeps foreign lines and comments intact.
- Unit (Mac): parsing of `Tailscale status --json`, `print-disabled`, the
  `Permission denied (…)` methods list, and `--getblockall` output.
- Manual, on the developer's Mac and iPhone:
  - fresh checklist on a Mac with Remote Login off → one admin prompt → all ✓;
  - pair, then connect over Tailscale on cellular;
  - Deny, expired code, and second scan of a used code;
  - Remove, then the phone shows "doesn't accept this phone";
  - Turn Off Phone Access restores password logins (probe shows
    `password`/`keyboard-interactive` again);
  - from a phone session, `cat` a file in `~/Documents` behaves the same as
    in the Mac window (folder privacy follows Lostty, not sshd);
  - the developer re-pairs and the two hand-added `lostty-mobile` lines are
    removed with their OK.

## Out of scope

Distribution (TestFlight then App Store; notarized Mac download) — the next
spec. Keeping the Mac awake with the lid closed. Several Macs per phone.
Lostty's own SSH server. Bundled tmux.

## Risks

- TLS with a pre-shared key in Network framework (`sec_protocol_options_add_pre_shared_key`)
  is the least-used piece; verify it on the 27 SDKs first, before building UI
  around it.
- Citadel must let the client limit host key algorithms to `ssh-ed25519`;
  if it can't, the pin check compares against whichever key type sshd
  presents and the QR carries the ECDSA host key as well.
- iOS shows the local-network prompt on first pairing; if the customer
  declines, pairing can't find the Mac. The phone detects the failure and
  points to Settings → Privacy → Local Network.
- A customer's own sshd config (an earlier drop-in or a `Match` block) can
  keep password logins on; the probe shows ⚠ rather than claiming success.
- macOS could change how Remote Login is toggled; the checklist re-check
  makes a silent failure visible.
