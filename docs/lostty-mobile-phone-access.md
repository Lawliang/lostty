# Lostty on your iPhone

Open your Mac's Lostty sessions from your iPhone, anywhere, over your own
Tailscale. Nothing goes through a Lostty server; there isn't one.

## Set up (once)

1. Install [Tailscale](https://tailscale.com/download) on your Mac and your
   iPhone, and sign in to both with the same account.
2. On the Mac, open Lostty → **Phone Access…**. Fix any row that isn't ✓:
   - **tmux**: `brew install tmux`.
   - **Remote Login** and **Password logins off**: one admin password prompt
     turns on Remote Login and allows only key logins. You can skip turning
     password logins off, but anyone who can reach your Mac could then try
     your password over SSH.
   - **Terminal definition**: click Install.
3. Click **Pair a Phone…**. On the iPhone, open Lostty, tap **Pair with Mac**,
   and scan the code. Click **Allow** on the Mac.

Your phone can reach the Mac only while the Mac is awake and Lostty is open.

## Lost phone

Open Lostty → Phone Access on the Mac and click **Remove** next to it. If you
can't get to Lostty, delete the line ending in `lostty-phone:<id>` from
`~/.ssh/authorized_keys`.

## Turning it off

Phone Access → **Turn Off Phone Access…** removes every paired phone and
offers to turn password logins back on. Remote Login stays as it is; turn it
off in System Settings → General → Sharing if you don't use it.

If you deleted Lostty instead, clean up by hand:

- remove the lines ending in `lostty-phone:…` from `~/.ssh/authorized_keys`;
- `sudo rm /etc/ssh/sshd_config.d/000-lostty.conf` to allow password logins again;
- optionally `rm ~/.terminfo/78/xterm-ghostty ~/.terminfo/67/ghostty`.

## Troubleshooting

- **"Couldn't find your Mac nearby"** while pairing: keep the code open on the
  Mac, keep the phone close, and allow Local Network access for Lostty on both.
- **"Can't reach your Mac"**: check Tailscale is on on both, signed into the
  same account, and the Mac is awake.
- **"This Mac's identity changed"**: if you reinstalled macOS, pair again.
  Otherwise don't connect; something else is answering at that address.
- **"Your Mac doesn't accept this phone"** right after pairing: in System
  Settings → General → Sharing → Remote Login, check that "Allow access for"
  includes your user.
