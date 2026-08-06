#!/usr/bin/env bash
# Paste the Windows clipboard into the current pane.
#
# tmux's own paste-buffer only knows tmux's internal buffer, which is a
# different thing from the Windows clipboard. And `mouse on` makes tmux swallow
# the right/middle click that Windows Terminal would otherwise paste with, so
# without this bridge there is no way to get a Windows-side copy into a pane.
set -euo pipefail

# Get-Clipboard emits CRLF. The stray \r would submit the line the instant it
# lands, running a half-pasted command.
clip=$(powershell.exe -NoProfile -NonInteractive -Command Get-Clipboard 2>/dev/null | sed 's/\r$//')

if [ -z "$clip" ]; then
	tmux display-message "clipboard is empty"
	exit 0
fi

# printf drops the trailing newline $() already stripped, so pasting a URL
# leaves the cursor on the same line instead of executing it. Interior newlines
# in a multi-line copy survive.
printf '%s' "$clip" | tmux load-buffer -

# -p brackets the paste so the shell treats it as literal text, not as typing.
tmux paste-buffer -p ${TMUX_PANE:+-t "$TMUX_PANE"}
