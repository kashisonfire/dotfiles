#!/usr/bin/env bash
# Create-or-attach a tmux session by name.
#
#   session.sh NAME [DIR ...]      one window per DIR, named after its basename
#   session.sh -n COUNT NAME [DIR] COUNT windows, all in DIR (default ~/code)
#
# Builds the shape of a session and nothing else. Windows are left sitting at a
# shell in their directory; what runs in them is the caller's business.
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
	# One directory, repeated.
	repeated=${dirs[0]:-$HOME/code}
	dirs=()
	for ((i = 0; i < count; i++)); do
		dirs+=("$repeated")
	done
elif [[ ${#dirs[@]} -eq 0 ]]; then
	dirs=("$HOME/code")
fi

# The first window's id is captured rather than its name, because -n mode gives
# every window the same name and a name target would resolve to whichever of them
# tmux matched first.
first=${dirs[0]}
home=$(tmux new-session -d -s "$session" -n "$(basename "$first")" \
	-c "$first" -P -F '#{window_id}')

for dir in "${dirs[@]:1}"; do
	tmux new-window -t "$session" -n "$(basename "$dir")" -c "$dir"
done

tmux select-window -t "$home"
attach
