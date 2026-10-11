# Lostty: shell signals for panes on Lostty's private tmux (tmux -L lostty).
#
# tmux keeps OSC 7 and OSC 133 for itself, so this re-sends the ones Lostty
# relies on wrapped in tmux's DCS passthrough (Lostty's tmux.conf sets
# allow-passthrough on), which reaches every attached client: the Mac window
# and the phone alike.
#
#   OSC 7          cwd: auto-skin, new tabs/splits      every prompt
#   OSC 133 C / D  command started / finished + status  around each command
#   LOSTTY_PROJECT the project path (git root, else cwd) every prompt
#
# Everything is re-sent at every prompt because a client that attaches later
# (the phone) only sees what comes after it attaches.
#
# Never sends OSC 133 A, B or P: Ghostty does a fresh-line on those, which
# would move its cursor behind tmux's back.
#
# Sourced by .zshenv in this directory, in interactive shells.

[[ -n $LOSTTY_TMUX && -n $TMUX ]] || builtin return 0

# Wraps one escape sequence in tmux's DCS passthrough (ESC inside doubled).
_lostty_passthrough() {
    builtin local e=$'\e'
    builtin print -rn -- "${e}Ptmux;${1//$e/$e$e}${e}\\"
}

_lostty_osc() { _lostty_passthrough $'\e]'"$1"$'\a' }

# The project a directory belongs to: its git root, else the directory.
_lostty_project_of() {
    builtin local root
    root=$(command git -C "$1" rev-parse --show-toplevel 2>/dev/null)
    [[ -n $root ]] || root=$1
    builtin print -rn -- "$root"
}

builtin typeset -g _lostty_pwd= _lostty_project= _lostty_project_b64= _lostty_ran=

_lostty_precmd() {
    builtin local st=$?
    if [[ -n $_lostty_ran ]]; then
        _lostty_osc "133;D;$st"
        _lostty_ran=
    fi
    _lostty_osc "7;kitty-shell-cwd://$HOST$PWD"
    if [[ $PWD != $_lostty_pwd ]]; then
        _lostty_pwd=$PWD
        builtin local project
        project=$(_lostty_project_of "$PWD")
        if [[ $project != $_lostty_project ]]; then
            _lostty_project=$project
            _lostty_project_b64=$(builtin print -rn -- "$project" | command base64 | command tr -d '\n')
            # Name the session after the project, in the background.
            [[ -x $LOSTTY_BIN ]] && { "$LOSTTY_BIN" +tmux-rename -- "$project" >/dev/null 2>&1 &! }
        fi
    fi
    _lostty_osc "1337;SetUserVar=LOSTTY_PROJECT=$_lostty_project_b64"
}

_lostty_preexec() {
    _lostty_osc "133;C"
    _lostty_ran=1
}

builtin autoload -Uz add-zsh-hook
add-zsh-hook precmd _lostty_precmd
add-zsh-hook preexec _lostty_preexec
