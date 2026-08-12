# dotfiles

WezTerm + tmux configuration, shared across machines.

## Layout

```
wezterm/wezterm.lua   read by WezTerm on the Windows side
tmux/tmux.conf        symlinked to ~/.tmux.conf inside WSL
tmux/*.sh             symlinked into ~/.tmux/
tmux/cheatsheet.txt   symlinked into ~/.tmux/, where which-key reads it
tmux/agent-status.py  symlinked into ~/.claude/hooks/, run by Claude Code
```

## Why the repo lives on the Windows filesystem

WezTerm runs as a Windows process; tmux runs inside WSL. Both need to read from
one checkout, and the two directions are not symmetric:

- WSL can follow its own symlinks into `/mnt/c`.
- Windows **cannot** follow a symlink created by WSL. It sees a Linux reparse
  point and fails with `The file cannot be accessed by the system`.

So the checkout sits on `C:` where Windows reads it natively, and WSL reaches it
through `/mnt/c`. The reverse layout would force WezTerm to load its config over
a `\\wsl.localhost\` path, making the terminal that launches WSL depend on WSL
already running.

`.wezterm.lua` is not symlinked at all. Creating a Windows symlink needs admin
rights or Developer Mode, so WezTerm is pointed at the repo with the
`WEZTERM_CONFIG_FILE` environment variable instead, which needs neither.

## Setup on a new machine

**1. Clone to the Windows home directory**

```powershell
git clone <repo-url> $env:USERPROFILE\dotfiles
```

**2. Point WezTerm at it** (PowerShell, no admin needed)

```powershell
setx WEZTERM_CONFIG_FILE "$env:USERPROFILE\dotfiles\wezterm\wezterm.lua"
```

`setx` only affects processes started afterwards. Fully quit and reopen WezTerm.

**3. Link the tmux files** (WSL)

```bash
DOT=/mnt/c/Users/$USER/dotfiles          # adjust if the Windows username differs
ln -sfn "$DOT/tmux/tmux.conf" ~/.tmux.conf
mkdir -p ~/.tmux
for f in cheatsheet.txt session.sh pick.sh; do
  ln -sfn "$DOT/tmux/$f" ~/.tmux/$f
done
```

**4. Wire up the agent status hooks** (WSL)

```bash
mkdir -p ~/.claude/hooks
ln -sfn "$DOT/tmux/agent-status.py" ~/.claude/hooks/agent-status.py
```

Then add this to `~/.claude/settings.json`, which is **not** in this repo, so it
does not travel with a `git pull`. All four events run the same script:

```json
"hooks": {
  "SessionStart":  [{ "hooks": [{ "type": "command", "command": "python3 \"$HOME/.claude/hooks/agent-status.py\"" }] }],
  "Stop":          [{ "hooks": [{ "type": "command", "command": "python3 \"$HOME/.claude/hooks/agent-status.py\"" }] }],
  "SubagentStop":  [{ "hooks": [{ "type": "command", "command": "python3 \"$HOME/.claude/hooks/agent-status.py\"" }] }],
  "SessionEnd":    [{ "hooks": [{ "type": "command", "command": "python3 \"$HOME/.claude/hooks/agent-status.py\"" }] }]
}
```

Nothing breaks without it: the window list falls back to the glyph Claude Code
puts in its own terminal title, which is what the bar read before these hooks
existed. What it loses is the `●N` badge, described under Reading the bar.

**5. Install tmux plugins**

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

Then start tmux and press `prefix + I` (prefix is `C-a`).

`prefix + Space` opens tmux-which-key's menu, and its `?` entry is what displays
`cheatsheet.txt`. That entry is not upstream, and it lives in the plugin's own
`config.yaml` rather than in this repo - the plugin gitignores that file, so a
fresh install comes up without it. Add it back in
`~/.tmux/plugins/tmux-which-key/config.yaml`, after the `show-messages` item,
and move the `+Keys` entry that holds `?` upstream over to `/`:

```yaml
  - name: Cheatsheet
    key: '?'
    command: 'display-popup -E -w 48 -h 90% -x R -y 1 "less -R ~/.tmux/cheatsheet.txt"'
```

## Reading the bar

Each window in the status bar is its index, a state marker, and a label.

```
 3 ◐ Fix tmux status for run…     working
 3 ✳ Fix tmux status for run…     idle, nothing pending
 3 ●2 Fix tmux status for run…    two background agents or workflows still running
 3 ✳ Fix tmux status for run…!    rang the bell: finished, or waiting on a prompt
 3 apartments-web                 no agent in this window, so its directory
```

`◐` and `✳` come from Claude Code's own terminal title and track its main loop.
`●N` is the part the title cannot express: work handed to a background subagent or
a workflow outlives the turn that launched it, so without the badge those windows
drop back to `✳` and read as finished while several agents are still going. It
counts subagents and workflows, not background shells, since a dev server never
finishes. Panes are counted individually, so two agents split into one window show
up as `●1●1`.

The label is the conversation's topic, which Claude Code generates once when the
subject first becomes clear, so it names the subject rather than the current
activity, and it can lag behind where a long session ended up. `/rename` in a
session sets it, and short names survive the truncation better.

## Sessions

`tmux/session.sh` creates a session or attaches to it if it already exists.

```bash
~/.tmux/session.sh -n 5 cpna              # 5 windows in ~/code
~/.tmux/session.sh dev ~/code/apartments-web ~/code/apartments-cpna
```

It builds the shape and nothing else: windows are left at a shell in their
directory, so `cc` or `ccc` is what starts an agent in one.

`tmux/pick.sh` is the front door: an fzf list of live sessions merged with
whatever tmux-resurrect has on disk, arrow keys and Enter, with a preview of each
session's windows and directories. Picking a saved one restores it first, and the
`+ new session` row at the bottom asks for a name and hands off to `session.sh`.
Detaching returns to the list; Escape leaves you at a shell.

It needs two lines in `~/.zshrc`, which is **not** in this repo, so they do not
travel with a `git pull`:

```bash
alias ts="$HOME/.tmux/pick.sh"

# At the very bottom. The $TMUX test is what keeps it from firing inside every
# new pane and split rather than only at WezTerm start.
if [[ -o interactive && -z $TMUX && -t 1 ]]; then
    "$HOME/.tmux/pick.sh"
fi
```

## Surviving a restart

Detaching is free - the tmux server is an ordinary process and WSL keeps the VM
alive while it runs, so closing WezTerm does not end the session. `wsl
--shutdown` and a Windows restart do.

Nothing can preserve a live process across that, so tmux-resurrect saves the
shape instead: windows, panes, layout, per-pane working directory, and
scrollback. tmux-continuum snapshots it every 15 minutes.

```
prefix + C-s    save now
prefix + C-r    restore
```

Restore is manual on purpose - see the comment above `@continuum-restore` in
`tmux.conf`. Restored agent panes come back as shells in the right directory;
`claude --continue` resumes that directory's last conversation.

## Syncing

`git pull` to pick up changes made on another machine. tmux reloads with
`prefix + r`; WezTerm reloads its config automatically on save.

## Notes

- `.gitattributes` pins `eol=lf`. The repo lives on NTFS but `tmux/*.sh` run
  under bash, and CRLF line endings break the shebang.
- `wezterm.lua` sets `default_domain = "WSL:Ubuntu"`. That is the one line that
  has to change if this is ever used on macOS or native Linux. `font_size` is
  the other machine-specific value - it is translated to Windows' 96 DPI
  baseline and nudged up for the 27" 1440p primary, so it is worth revisiting
  per display rather than guarding.
