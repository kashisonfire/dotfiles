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
for f in cheatsheet.txt dev-session.sh paste-from-windows.sh; do
  ln -sfn "$DOT/tmux/$f" ~/.tmux/$f
done
```

**4. Install tmux plugins**

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

Then start tmux and press `prefix + I` (prefix is `C-a`).

## Syncing

`git pull` to pick up changes made on another machine. tmux reloads with
`prefix + r`; WezTerm reloads its config automatically on save.

## Notes

- `.gitattributes` pins `eol=lf`. The repo lives on NTFS but `tmux/*.sh` run
  under bash, and CRLF line endings break the shebang.
- `wezterm.lua` sets `default_domain = "WSL:Ubuntu"`. That is the only
  machine-specific line; it needs a guard if this is ever used on macOS or
  native Linux.
