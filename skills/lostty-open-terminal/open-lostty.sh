#!/bin/zsh
# Opens a new, visible Lostty window in a folder and starts Claude there with a directive as its first message.
#
#   open-lostty.sh <folder> <directive-file> [--agent claude|none]
#
# 1. Asks Lostty for a window (the @lostty_new_<id> request). 2. If Lostty doesn't answer in 15 s, opens the folder
# with Lostty instead (`open -a`). 3. Checks a window really shows the new session (attached), else kills the session
# and fails: never leaves a hidden one behind. 4. Types `claude "$(cat <copy of the directive>)"` into it.
# Prints "window: <session id> <session name>" on success. Exit codes: 2 usage, 3 not exactly one Lostty running,
# 4 no visible window appeared. The window is titled with its session name.

set -u
folder=${1:-} directive=${2:-} agent=claude
[[ ${3:-} == --agent ]] && agent=${4:-claude}
[[ -n $folder && -d $folder && -n $directive && -f $directive ]] || {
  echo "usage: open-lostty.sh <existing folder> <directive file> [--agent claude|none]" >&2; exit 2; }
folder=${folder:A}
tmux=(/opt/homebrew/bin/tmux -u -L lostty -f /dev/null)
app=/Applications/Lostty.app

# Two Lostty apps (e.g. a Debug build) both claim requests and open duplicate windows.
running=$(pgrep -f "MacOS/lostty$" | wc -l | tr -d ' ')
if [[ $running != 1 ]]; then
  echo "need exactly one Lostty running, found $running:" >&2; pgrep -fl "MacOS/lostty$" >&2; exit 3
fi

# The directive is kept in a file the new session reads, so quotes and newlines survive typing.
store=$HOME/.claude/lostty-directives; mkdir -p $store
id=$(openssl rand -hex 6)
cp $directive $store/$id.txt

sessions() { $tmux list-sessions -F '#{session_id}' 2>/dev/null | sort; }
before=$(sessions)
session=""

# 1. Lostty's own request: it opens the window and answers with the session id ("$12") or "!why".
# From a canvas card, "from" names this pane: Lostty opens a card beside it, in its zone.
$tmux set-option -g "@lostty_new_$id" "{\"id\":\"$id\",\"folder\":\"$folder\",\"from\":\"${LOSTTY_SURFACE:-}\"}"
$tmux wait-for -S lostty-changed
for i in {1..30}; do
  answer=$($tmux show-options -gqv "@lostty_made_$id")
  [[ -n $answer ]] && break
  perl -e 'select(undef,undef,undef,0.5)'
done
$tmux set-option -gu "@lostty_new_$id" 2>/dev/null; $tmux set-option -gu "@lostty_made_$id" 2>/dev/null
case $answer in
  \$*) session=$answer ;;
  \!*) echo "Lostty refused: ${answer#!}" >&2 ;;
  *)   echo "Lostty didn't answer the request; opening the folder with Lostty instead" >&2 ;;
esac

# 2. Fallback: open the folder with Lostty, then find the session that appeared.
if [[ -z $session ]]; then
  open -a $app "$folder"
  for i in {1..30}; do
    session=$(comm -13 <(echo "$before") <(sessions) | head -1)
    [[ -n $session ]] && break
    perl -e 'select(undef,undef,undef,0.5)'
  done
fi
[[ -n $session ]] || { echo "no new Lostty session appeared" >&2; exit 4; }

# 3. A window must show it.
for i in {1..20}; do
  [[ $($tmux display-message -p -t "$session" '#{session_attached}' 2>/dev/null) -ge 1 ]] && break
  perl -e 'select(undef,undef,undef,0.5)'
done
if [[ $($tmux display-message -p -t "$session" '#{session_attached}' 2>/dev/null) -lt 1 ]]; then
  $tmux kill-session -t "$session" 2>/dev/null
  echo "session $session opened but no window shows it; killed it" >&2; exit 4
fi

# The window's title is its session's name (the folder's, e.g. "zones-2"), which stays put over the agent's own
# titles and matches what +peers and ListAgents show. Lostty shows a session label as the title, as from the phone.
name=$($tmux display-message -p -t "$session" '#{session_name}')
$tmux set-option -t "$session" @lostty_label "$name" \; wait-for -S lostty-changed

# 4. Start the agent with the directive as its first message, once the shell is up.
perl -e 'select(undef,undef,undef,1.5)'
if [[ $agent == claude ]]; then
  $tmux send-keys -t "$session" -l "claude \"\$(cat '$store/$id.txt')\""
else
  $tmux send-keys -t "$session" -l "cat '$store/$id.txt'"
fi
$tmux send-keys -t "$session" Enter
echo "window: $session $name"
