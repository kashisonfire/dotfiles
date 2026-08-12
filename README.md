# dotfiles

WezTerm + tmux configuration, shared across machines.

## Layout

```
wezterm/wezterm.lua   read by WezTerm on the Windows side
tmux/tmux.conf        symlinked to ~/.tmux.conf inside WSL
tmux/*.sh             symlinked into ~/.tmux/
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
for f in cheatsheet.txt session.sh pick.sh paste-from-windows.sh; do
  ln -sfn "$DOT/tmux/$f" ~/.tmux/$f
done
```

**4. Install tmux plugins**

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

Then start tmux and press `prefix + I` (prefix is `C-a`).

## Sessions

`tmux/session.sh` creates a session or attaches to it if it already exists.

```bash
~/.tmux/session.sh -n 5 cpna              # 5 agent windows in ~/code
~/.tmux/session.sh dev ~/code/apartments-web ~/code/apartments-cpna
```

Every window opens an agent; quitting one leaves a shell behind rather than
closing the window.

`tmux/pick.sh` is the front door: an fzf list of live sessions merged with
whatever tmux-resurrect has on disk, arrow keys and Enter, with a preview of each
session's windows and directories. Picking a saved one restores it first.
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
- `wezterm.lua` sets `default_domain = "WSL:Ubuntu"`. That is the only
  machine-specific line; it needs a guard if this is ever used on macOS or
  native Linux.
