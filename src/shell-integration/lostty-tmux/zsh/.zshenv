# Lostty: zsh startup for panes on Lostty's private tmux. `+tmux-launch`
# points ZDOTDIR here. This restores the user's ZDOTDIR and runs their
# .zshenv; in interactive shells it then loads Ghostty's own zsh integration
# (titles, cursor shape, sudo/ssh helpers; its OSC 7/133 stop at tmux) and
# lostty-tmux.zsh, which re-sends what Lostty needs through tmux.
#
# Sourced with aliases possibly enabled, so builtins are quoted.

if [[ -n "${LOSTTY_ZDOTDIR+X}" ]]; then
    'builtin' 'export' ZDOTDIR="$LOSTTY_ZDOTDIR"
    'builtin' 'unset' 'LOSTTY_ZDOTDIR'
else
    'builtin' 'unset' 'ZDOTDIR'
fi

{
    'builtin' 'typeset' _lostty_file=${ZDOTDIR-$HOME}"/.zshenv"
    [[ ! -r "$_lostty_file" ]] || 'builtin' 'source' '--' "$_lostty_file"
} always {
    if [[ -o 'interactive' ]]; then
        _lostty_file="$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
        if [[ -r "$_lostty_file" ]]; then
            'builtin' 'autoload' '-Uz' '--' "$_lostty_file"
            "${_lostty_file:t}"
            'builtin' 'unfunction' '--' "${_lostty_file:t}"
        fi
        _lostty_file="${${(%):-%x}:A:h}/lostty-tmux.zsh"
        [[ ! -r "$_lostty_file" ]] || 'builtin' 'source' '--' "$_lostty_file"
    fi
    'builtin' 'unset' '_lostty_file'
}
