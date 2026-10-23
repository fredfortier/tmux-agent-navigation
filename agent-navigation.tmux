#!/usr/bin/env bash
# Additive TPM/manual entrypoint. Own only these documented bindings/options.
set -euo pipefail
for nav_dependency in tmux nvim jq; do
    command -v "$nav_dependency" >/dev/null || { echo "Missing dependency: $nav_dependency" >&2; exit 1; }
done
nav_version=$(tmux -V)
if [[ ! $nav_version =~ ^tmux\ ([0-9]+)\.([0-9]+) ]] ||
    ((BASH_REMATCH[1] < 3 || (BASH_REMATCH[1] == 3 && BASH_REMATCH[2] < 4))); then
    echo 'tmux-agent-navigation requires tmux 3.4 or newer' >&2
    exit 1
fi
nvim --headless -u NONE -i NONE -c 'if !has("nvim-0.11") | cquit | endif' +q
nav_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# POSIX single-quote escaping for tmux's run-shell, including checkout spaces.
quote() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
nav_command=$(quote "$nav_root/bin/agent-navigation")
tmux bind-key -T copy-mode-vi g switch-client -T agent-navigation-g
tmux bind-key -T agent-navigation-g g send-keys -X history-top
tmux bind-key -T agent-navigation-g f run-shell -b "$nav_command open #{pane_id}"
tmux bind-key -T agent-navigation-g n run-shell -b "$nav_command open #{pane_id} split"
tmux bind-key -T agent-navigation-g Escape switch-client -T root
tmux bind-key -T agent-navigation-g q send-keys -X cancel
tmux bind-key e run-shell -b "$nav_command toggle #{pane_id}"
# Status is opt-in: users can insert this format in their existing status line.
tmux set-option -g @agent-status '#{?@nav_parent,EDITOR | :q return | prefix e #{?window_zoomed_flag,split,zoom},}'
# Optional tmux-thumbs integration. Users install upstream themselves.
nav_thumbs=$(tmux show-option -gqv @agent-thumbs-path)
if [[ -n $nav_thumbs ]]; then
    [[ -f $nav_thumbs/tmux-thumbs.tmux ]] || { echo 'Invalid @agent-thumbs-path' >&2; exit 1; }
    tmux set-option -g @thumbs-key F
    tmux set-option -g @thumbs-upcase-command "$nav_command thumb \"{}\""
    # Upstream replaces {} safely after reading the option. A literal $THUMB
    # is escaped by older tmux versions when the option crosses its CLI.
    tmux set-option -g @thumbs-command 'tmux set-buffer -- "{}"; tmux display-message -l "Copied hint"'
    tmux set-option -g @thumbs-regexp-0 '[.\w@~-]+[ \t]+\([.\w@~/-]+(?::[0-9]+(?::[0-9]+)?|#L[0-9]+(?:-L?[0-9]+)?)?\)'
    tmux set-option -g @thumbs-regexp-1 '(?:(?:~?/|[.\w@~-]+/)[.\w@~/-]+|[.\w@~-]+\.[\w.-]+)(?::[0-9]+(?::[0-9]+)?|#L[0-9]+(?:-L[0-9]+)?)?'
    /bin/bash "$nav_thumbs/tmux-thumbs.tmux"
    tmux bind-key F run-shell -b "$(quote "$nav_root/bin/thumbs-pick")"
fi
