#!/usr/bin/env bash
# Pick a tmux session out of an fzf list and attach to it.
#
# The list merges live sessions with the ones tmux-resurrect has on disk, because
# which of the two holds anything depends on when you run it: straight after a
# restart there is no server and only the save file remembers yesterday, while
# mid-morning both exist and overlap. Live wins a name collision, since attaching
# to a session that is already up costs nothing and restoring does not.
#
# Arrow keys and Enter, or type to filter. Escape leaves you at a shell.
#
# Reached as `ts`, and run from ~/.zshrc for any interactive shell that is not
# already inside tmux.
set -uo pipefail

# fzf lives in ~/.fzf/bin, which is on PATH for a zsh login shell and not
# reliably anywhere else. Same reason the prefix+g binding in tmux.conf prepends
# it before shelling out to zoxide.
[[ -d $HOME/.fzf/bin ]] && PATH="$HOME/.fzf/bin:$PATH"

TAB=$'\t'
RESTORE=$HOME/.tmux/plugins/tmux-resurrect/scripts/restore.sh
BOOTSTRAP=_restoring

resurrect_dir() {
	local dir
	dir=$(tmux show-option -gqv @resurrect-dir 2>/dev/null)
	if [[ -n ${dir:-} ]]; then
		echo "${dir/#\~/$HOME}"
	else
		# The default out of tmux-resurrect's own helpers.sh.
		echo "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
	fi
}

SAVE=$(resurrect_dir)/last

shorten() { sed "s|$HOME|~|g"; }

# The windows of one session, for the fzf preview. This is what tells two saved
# sessions apart once the names have gone stale, and it is the only place those
# ephemeral treehouse worktree paths are written down.
#
# The saved side reads pane lines rather than window lines because only panes
# carry a directory. Field order is the one restore.sh unpacks. Agent panes are
# labelled with the pane title, which is the status Claude Code last published --
# i.e. what that agent was in the middle of when the machine went down.
preview() {
	local name=$1 state=$2
	case $state in
	live)
		tmux list-panes -s -t "$name" -F \
			"#{window_index}${TAB}#{?#{==:#{pane_current_command},claude},#{pane_title},#{pane_current_command}}${TAB}#{pane_current_path}" 2>/dev/null
		;;
	saved)
		awk -F'\t' -v s="$name" '
			$1 == "pane" && $2 == s {
				sub(/^:/, "", $8)
				label = ($10 == "claude" && $7 != "") ? $7 : $10
				print $3 "\t" label "\t" $8
			}' "$SAVE" 2>/dev/null
		;;
	esac | shorten | column -t -s "$TAB"
}

if [[ ${1:-} == --preview ]]; then
	preview "${2:-}" "${3:-}"
	exit 0
fi

# name<TAB>state<TAB>windows. Live is emitted first so the dedupe keeps it.
collect() {
	tmux list-sessions -F "#{session_name}${TAB}live${TAB}#{session_windows}" 2>/dev/null | sort
	[[ -f $SAVE ]] && awk -F'\t' '
		$1 == "window" { n[$2]++ }
		END { for (s in n) print s "\tsaved\t" n[s] }' "$SAVE" | sort
	return 0
}

# fzf is handed <display><TAB><name><TAB><state> and told to show field 1 only,
# so the machine-readable name survives whatever the display column does to it.
menu() {
	local records width stamp name state windows noun extra
	records=$(collect | awk -F'\t' '!seen[$1]++')
	width=$(awk -F'\t' 'length($1) > m { m = length($1) } END { print (m < 4 ? 4 : m) }' <<<"$records")
	stamp=$([[ -f $SAVE ]] && date -r "$SAVE" '+%H:%M' 2>/dev/null)

	while IFS=$TAB read -r name state windows; do
		[[ -z $name ]] && continue
		# The noun is padded rather than appended so a single-window session does
		# not shunt the timestamp column left by one.
		[[ $windows == 1 ]] && noun=window || noun=windows
		extra=""
		[[ $state == saved && -n $stamp ]] && extra="  $stamp"
		printf "%-${width}s  %-5s  %2s %-7s%s\t%s\t%s\n" \
			"$name" "$state" "$windows" "$noun" "$extra" "$name" "$state"
	done <<<"$records"

	printf '+ new session\t\tnew\n'
}

attach() {
	if [[ -n ${TMUX:-} ]]; then
		tmux switch-client -t "$1"
	else
		tmux attach-session -t "$1"
	fi
}

fzf_opts=(
	--delimiter="$TAB" --with-nth=1
	--height=60% --layout=reverse --border=rounded
	--prompt='session '
	--header='↑↓ move   enter attach   esc shell'
	# The counter and its horizontal rule are noise for a list this short, and
	# hiding them puts the header directly above the sessions.
	--info=hidden
	# wrap, because a treehouse worktree path is longer than any preview pane and
	# the tail is the part that identifies it.
	--preview="$0 --preview {2} {3}"
	--preview-window='right,50%,border-left,wrap'
	# bg stays at -1 so window_background_opacity from wezterm.lua still shows
	# through the list; only the current row takes a solid overlay.
	#
	# gutter is a *foreground* glyph, not a background: fzf draws ▌ down the left
	# of the list and paints it in this colour. At -1 that resolves to the
	# terminal's default foreground, which turns a quiet rule into a bright bar on
	# every row. #393552 is the colour pane-border-style already uses, so the rule
	# reads as the same furniture as a tmux pane edge.
	--color=fg:#908caa,bg:-1,hl:#ea9a97
	--color=fg+:#e0def4,bg+:#393552,hl+:#ea9a97
	--color=border:#44415a,gutter:#393552,header:#3e8fb0
	--color=spinner:#f6c177,info:#9ccfd8
	--color=pointer:#c4a7e7,marker:#eb6f92,prompt:#908caa
)

while :; do
	selection=$(menu | fzf "${fzf_opts[@]}") || break
	[[ -z $selection ]] && break

	name=$(cut -f2 <<<"$selection")
	state=$(cut -f3 <<<"$selection")

	case $state in
	live)
		attach "$name"
		;;
	saved)
		# restore.sh drives everything through the tmux CLI, so it needs a server
		# to talk to. `tmux start-server` is NOT enough: a server holding no
		# sessions exits immediately, so every call after it reports "no server
		# running" and the restore quietly does nothing at all. A throwaway session
		# is what keeps the server up long enough to be restored into, and run-shell
		# is how continuum invokes this same script.
		#
		# Restores every session in the save file rather than the one asked for:
		# restore.sh takes no arguments and has no per-session entry point, so the
		# others arrive detached and idle. Cheap here only because agent panes come
		# back as shells, `claude` being absent from @resurrect-processes.
		tmux new-session -d -s "$BOOTSTRAP" -c "$HOME" 2>/dev/null
		tmux run-shell "$RESTORE" >/dev/null 2>&1
		tmux kill-session -t "$BOOTSTRAP" 2>/dev/null
		# Killing the bootstrap takes the server with it when the restore produced
		# nothing, which is the outcome worth showing rather than papering over.
		tmux has-session -t="$name" 2>/dev/null || continue
		attach "$name"
		;;
	new)
		read -r -p 'session name: ' name || break
		[[ -z $name ]] && continue
		# A subshell, because session.sh ends in `exec tmux attach`. The exec
		# replaces the subshell rather than this script, so detaching still lands
		# back on the picker.
		("$HOME/.tmux/session.sh" "$name")
		;;
	esac

	# Inside tmux the client has already been switched and there is nothing to
	# come back to, so redrawing the picker in the pane just left is noise.
	[[ -n ${TMUX:-} ]] && break
done

exit 0
