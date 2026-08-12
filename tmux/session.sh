#!/usr/bin/env bash
# Create-or-attach a tmux session by name.
#
#   session.sh NAME [DIR ...]      one window per DIR, named after its basename
#   session.sh -n COUNT NAME [DIR] COUNT windows, all in DIR (default ~/code)
#
# Every window opens an agent. Quitting one drops to a shell rather than closing
# the window, so a plain shell is always one /exit away and does not need its own
# flag or its own window.
#
# This lives outside ~/.tmux.conf on purpose. That file is re-sourced on every
# `prefix + r` reload, so window-spawning commands placed there would stack up a
# duplicate set of windows each time.
set -euo pipefail

usage() {
	printf 'usage: %s [-n COUNT] NAME [DIR ...]\n' "${0##*/}" >&2
	exit 2
}

count=0
while getopts ':n:' opt; do
	case $opt in
	n) count=$OPTARG ;;
	*) usage ;;
	esac
done
shift $((OPTIND - 1))

[[ $# -ge 1 ]] || usage
[[ $count =~ ^[0-9]+$ ]] || usage
session=$1
shift

attach() {
	# Plain `attach-session` errors out when already inside tmux; switch-client
	# is the nested path.
	if [[ -n ${TMUX:-} ]]; then
		exec tmux switch-client -t "$session"
	else
		exec tmux attach-session -t "$session"
	fi
}

# -t= is an exact-name match, so a session like "dev-scratch" won't satisfy a
# request for "dev".
if tmux has-session -t="$session" 2>/dev/null; then
	attach
fi

dirs=("$@")
if [[ $count -gt 0 ]]; then
	# One directory, repeated. Windows all get the same name, which is fine:
	# window-status-format reads the pane title for agent panes, so the bar shows
	# what each one is doing rather than what it was called.
	repeated=${dirs[0]:-$HOME/code}
	dirs=()
	for ((i = 0; i < count; i++)); do
		dirs+=("$repeated")
	done
elif [[ ${#dirs[@]} -eq 0 ]]; then
	dirs=("$HOME/code")
fi

# send-keys rather than passing the command to new-window: as the window's
# command, quitting the agent would take the window with it.
spawn() {
	local target=$1
	tmux send-keys -t "$target" 'claude' C-m
}

# Window ids rather than "$session:$name" targets, because names repeat in
# -n mode and a name target would resolve to whichever window matched first.
first=${dirs[0]}
window=$(tmux new-session -d -s "$session" \
	-n "$([[ $count -gt 0 ]] && echo claude || basename "$first")" \
	-c "$first" -P -F '#{window_id}')
spawn "$window"
home=$window

for dir in "${dirs[@]:1}"; do
	window=$(tmux new-window -t "$session" \
		-n "$([[ $count -gt 0 ]] && echo claude || basename "$dir")" \
		-c "$dir" -P -F '#{window_id}')
	spawn "$window"
done

tmux select-window -t "$home"
attach
