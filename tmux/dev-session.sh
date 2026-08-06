#!/usr/bin/env bash
# Default dev session: one window per active project.
#
# This lives outside ~/.tmux.conf on purpose. That file is re-sourced on every
# `prefix + r` reload, so window-spawning commands placed there would stack up
# a duplicate set of windows each time.
set -euo pipefail

S=dev

attach() {
	# Plain `attach-session` errors out when already inside tmux; switch-client
	# is the nested path.
	if [[ -n ${TMUX:-} ]]; then
		exec tmux switch-client -t "$S"
	else
		exec tmux attach-session -t "$S"
	fi
}

# -t= is an exact-name match, so a session like "dev-scratch" won't satisfy it.
if tmux has-session -t="$S" 2>/dev/null; then
	attach
fi

tmux new-session -d -s "$S" -n claude -c ~/code
# send-keys rather than `new-session ... claude`: as the window's command,
# quitting claude would close the window. This way it drops to a shell in ~/code.
tmux send-keys -t "$S":claude 'claude' C-m

tmux new-window -t "$S" -n apartments-web -c ~/code/apartments-web
tmux new-window -t "$S" -n apartments-cpna -c ~/code/apartments-cpna

tmux select-window -t "$S":claude
attach
