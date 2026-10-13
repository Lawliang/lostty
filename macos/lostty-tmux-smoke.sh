#!/bin/sh
# Lostty Mobile smoke test for panes in tmux sessions. Runs `+tmux-launch`
# inside a throwaway outer tmux (which gives it a terminal, as a Lostty pane
# would), then checks the session's tags and project name, the signals that
# come out of tmux passthrough, that `exit` ends the session, and the
# notice for a session that is gone. Only touches the session it creates.
# Usage: macos/lostty-tmux-smoke.sh   (after building the Debug app)
set -u
cd "$(dirname "$0")/.."
APP="$PWD/macos/build/Debug/Lostty.app/Contents"
BIN="$APP/MacOS/lostty"
RES="$APP/Resources/ghostty"
TMUX_BIN=$(command -v tmux || echo /opt/homebrew/bin/tmux)
SURFACE="ABCDEF01-0000-4000-8000-0000000000AA"
WORK=$(mktemp -d)
PROJECT="$WORK/my.project"
RAW="$WORK/raw"
mkdir -p "$PROJECT"
: > "$RAW"

cleanup() {
    "$TMUX_BIN" -L lostty list-sessions -F '#{session_id} #{@lostty_surface}' 2>/dev/null |
        awk -v s="$SURFACE" '$2 == s { print $1 }' |
        while read -r id; do "$TMUX_BIN" -L lostty kill-session -t "$id"; done
    "$TMUX_BIN" -L lostty-smoke kill-server 2>/dev/null
    rm -rf "$WORK"
}
fail() {
    echo "FAIL: $*"
    echo "--- outer pane:"
    "$TMUX_BIN" -L lostty-smoke capture-pane -p -t outer 2>/dev/null
    cleanup
    exit 1
}
# wait_for <what> <command…>: retries the command for up to 10 s.
wait_for() {
    what=$1
    shift
    n=0
    until "$@" >/dev/null 2>&1; do
        n=$((n + 1))
        [ "$n" -gt 50 ] && fail "timed out waiting for $what"
        sleep 0.2
    done
}
our_session() {
    "$TMUX_BIN" -L lostty list-sessions -F '#{@lostty_surface}|#{session_name}|#{@lostty_owner}|#{@lostty_shell}' 2>/dev/null |
        grep "^$SURFACE|"
}
named_and_tagged() { our_session | grep -q "^$SURFACE|my_project|$$|zsh\$"; }
gone() { ! our_session; }
our_id() {
    "$TMUX_BIN" -L lostty list-sessions -F '#{session_id} #{@lostty_surface}' 2>/dev/null |
        awk -v s="$SURFACE" '$2 == s { print $1 }'
}
attached() { "$TMUX_BIN" -L lostty list-clients -t "$(our_id)" | grep -q .; }
saw() { grep -qF "$1" "$RAW"; }
pane_says() { "$TMUX_BIN" -L lostty-smoke capture-pane -p -t outer | grep -qF "$1"; }

[ -x "$BIN" ] || { echo "FAIL: build the Debug app first ($BIN)"; exit 1; }
[ -f "$RES/shell-integration/lostty-tmux/tmux.conf" ] ||
    { echo "FAIL: $RES has no lostty-tmux; run zig build -Demit-macos-app=false, then rebuild the app"; exit 1; }

LAUNCH="env TMUX=/private/tmp/tmux-fake/default,1,0 TMUX_PANE=%99 TERM=xterm-ghostty TERMINFO='$APP/Resources/terminfo' LOSTTY_SURFACE=$SURFACE LOSTTY_APP_PID=$$ LOSTTY_BIN='$BIN' GHOSTTY_RESOURCES_DIR='$RES' SHELL=/bin/zsh '$BIN' +tmux-launch"
"$TMUX_BIN" -L lostty-smoke -f /dev/null new-session -d -s outer -x 120 -y 40 -c "$PROJECT" "$LAUNCH"
"$TMUX_BIN" -L lostty-smoke set -g remain-on-exit on
"$TMUX_BIN" -L lostty-smoke pipe-pane -t outer "cat >> '$RAW'"

wait_for "the pane's session" our_session
wait_for "the session named my_project, owned by this script, shell zsh" named_and_tagged

# Lostty's tmux.conf: a mouse drag copies and leaves copy mode (else typing
# is swallowed), and tmux's pane/menu mouse bindings are gone (no splits).
for t in copy-mode copy-mode-vi; do
    "$TMUX_BIN" -L lostty list-keys -T $t MouseDragEnd1Pane | grep -q 'copy-selection-and-cancel' ||
        fail "$t MouseDragEnd1Pane does not leave copy mode"
done
for k in MouseDown3Pane MouseDown3Empty C-MouseDrag1Pane C-MouseDrag1Empty M-MouseDrag1Pane MouseDown2Pane; do
    "$TMUX_BIN" -L lostty list-keys -T root 2>/dev/null | grep -q "^bind-key  *-T root  *$k " &&
        fail "root mouse binding $k is still bound"
done
"$TMUX_BIN" -L lostty list-keys -T root | grep -q ' WheelUpPane ' || fail "WheelUpPane is not bound"

# One command: 133;C before it, 133;D;<status> after, plus cwd and project.
"$TMUX_BIN" -L lostty-smoke send-keys -t outer 'tput colors > colors.txt' Enter
wait_for "OSC 133;D after a command" saw "]133;D;0"
saw "]133;C" || fail "no OSC 133;C"
saw "]7;kitty-shell-cwd://" || fail "no OSC 7"
saw "SetUserVar=LOSTTY_PROJECT=" || fail "no LOSTTY_PROJECT user var"
saw "]133;A" && fail "OSC 133;A reached the outer terminal"
[ "$(cat "$PROJECT/colors.txt")" = "256" ] || fail "TERM inside tmux is not a 256-color terminal"

# A crash: the session outlives its Lostty (owner now a dead pid). The
# window macOS restores has the same pane id, and picks the shell back up
# instead of starting a second session beside it.
before=$(our_id)
dead=$(sh -c 'echo $$')
"$TMUX_BIN" -L lostty set-option -t "$before" @lostty_owner "$dead"
"$TMUX_BIN" -L lostty-smoke respawn-pane -k -t outer -c "$PROJECT" "$LAUNCH"
wait_for "the restored pane to adopt its session" named_and_tagged
[ "$(our_id)" = "$before" ] || fail "restored pane started a new session ($(our_id)) instead of adopting $before"
wait_for "the restored pane to attach" attached

# Leaving the shell ends the session.
"$TMUX_BIN" -L lostty-smoke send-keys -t outer 'exit' Enter
wait_for "the session to end" gone

# Adopting a session that no longer exists: one-line notice, then a shell.
"$TMUX_BIN" -L lostty-smoke respawn-pane -k -t outer \
    "env -u TMUX -u TMUX_PANE LOSTTY_SURFACE=$SURFACE LOSTTY_APP_PID=$$ GHOSTTY_RESOURCES_DIR='$RES' SHELL=/bin/zsh '$BIN' +tmux-launch '--attach=\$999999'"
wait_for "the session-gone notice" pane_says "Lostty: that session has ended"

cleanup
echo PASS
