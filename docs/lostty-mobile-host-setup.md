# Lostty Mobile: manual Mac setup (Advanced)

Most people should use Lostty → Phone Access instead
(docs/lostty-mobile-phone-access.md). These are the steps it automates, for
setting up by hand.

1. **tmux**: `brew install tmux` (phase 1 needs it too).
2. **Remote Login**: System Settings → General → Sharing → Remote Login on,
   "Allow access for" → only your user.
3. **Keys only** (no passwords over SSH): create
   `/etc/ssh/sshd_config.d/000-lostty.conf` containing
   ```
   PasswordAuthentication no
   KbdInteractiveAuthentication no
   ```
   then toggle Remote Login off and on. Check with
   `ssh -o PreferredAuthentications=password localhost` — it must refuse.
4. **The phone's key**: in the phone app, Settings → Show This Phone's Key →
   share it to the Mac, and append it to `~/.ssh/authorized_keys` as
   `restrict,pty <key> lostty-phone:<any-id>` (`<key>` is the phone's key
   line, e.g. `ecdsa-sha2-nistp256 AAAA…`; `<any-id>` is any word without
   spaces). That exact form lets Phone Access list and remove the phone.
   `chmod 600 ~/.ssh/authorized_keys`.
5. **Terminal definition** (so tmux draws Lostty's terminal correctly):
   ```
   mkdir -p ~/.terminfo/78 ~/.terminfo/67 && cp /Applications/Lostty.app/Contents/Resources/terminfo/78/xterm-ghostty ~/.terminfo/78/ && cp /Applications/Lostty.app/Contents/Resources/terminfo/67/ghostty ~/.terminfo/67/
   ```
6. **Tailscale** on the Mac and the iPhone, signed in to the same tailnet,
   starting at login, with two-factor on the account. In the phone app use
   the Mac's Tailscale name (`your-mac.tailXXXX.ts.net`) or 100.x address.
7. **Awake in a bag** (optional): `sudo pmset -a disablesleep 1` keeps a
   closed MacBook awake (`sudo pmset -a disablesleep 0` to undo), or use
   Amphetamine with a battery floor. Set the Mac's Wi-Fi to auto-join the
   iPhone's hotspot. Expect heat under heavy builds and battery drain.
