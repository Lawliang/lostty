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
   - **Folder access** (optional): click Grant Now and allow Desktop, Documents
     and Downloads, so commands from your phone never wait on a macOS prompt.
3. Click **Pair a Phone…**. On the iPhone, open Lostty, tap **Pair with Mac**,
   and scan the code (or scan it with the Camera app and tap **Open in Lostty**). Click **Allow** on the Mac.

Your phone can reach the Mac only while the Mac is awake and Lostty is open.
To keep it awake with the lid closed, install the **Stay-awake permission** in
Phone Access, then choose **Stay Awake for Phone** from Lostty's menu bar icon.
While it's on, Low Power Mode is on whenever the lid is closed, and it turns
itself off at your battery floor (15% by default) or if the Mac gets too hot.

## Using it

Lostty on your phone lists your Mac's sessions and keeps the list current
while it's open. Each row says what's running:

- A Claude Code session shows its task ("Lostty UI redesign plan"), with
  **Waiting** when it's waiting for you or **Working** while it works.
  Waiting sessions come first. Opening one on the phone counts as seeing
  it, on the Mac too.
- Other sessions show their project. A session in `.claude/worktrees/<name>`
  shows as `<repo>/<name>`.
- Sessions no Mac window shows are under **Not open on Mac**.
- Swipe left on a row → **Rename** (or ⋯ → **Rename** in a terminal) to name
  a session. It's the same name as **Rename Tab…** on the Mac; leave it blank
  to go back to the automatic name.

If a session ends while you're in it, the terminal dims and says why
(closed on your Mac, Lostty quit on your Mac, closed from another phone, or
the shell exited) until you tap **Back to Sessions**. Typing `exit` yourself
goes straight back to the list. A dropped connection shows **Connection
lost — reconnecting…** and clears itself when the phone is back.

The Mac's menu bar icon lists the same sessions, with the same names and
order.

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
- `sudo rm /etc/sudoers.d/lostty` and `sudo pmset -a disablesleep 0`;
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
- **The Mac never sleeps** after Lostty was force-quit while Stay Awake was
  on: open Lostty once (it puts things back), or run
  `sudo pmset -a disablesleep 0`.
- **Rows show only folder names and never "Waiting"**: the Mac's Lostty is
  older than the phone app. Update Lostty on the Mac.
