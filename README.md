# dotfiles-devbox

zsh profile for the **Azure DevBox (WSL2/Debian)** work environment — kept
separate from the private macOS dotfiles repo (`blauwiggle/dotfiles`) so the two
never overwrite each other.

## Contents

- **`.zshrc`** — performance-tuned zsh config: cached `compinit`, cached kubectl
  completion, zinit turbo plugin loading, lazy `thefuck`, deduped `PATH`
  (`typeset -U`), `cd` mapped to zoxide (init kept last so its hook survives).
  Cross-platform-guarded, but installed only on this box.
- **`Brewfile.linux`** — linuxbrew CLI tools (`brew bundle --file=Brewfile.linux`).
- **`install.sh`** — installs Homebrew + zinit, runs the Brewfile, symlinks `.zshrc`.

## Install

```bash
./install.sh
```

> Under WSL, `install.sh` also runs the WSL deploy **and** restores Windows
> Terminal settings automatically (the latter only once a config has been
> captured into the repo). Run `./wsl/deploy.sh` or
> `./windows-terminal/deploy.sh` directly for a config-only update.

## WSL config (`wsl/`)

`.wslconfig` lives on the Windows C: drive and can't be stowed, so it is
**copied** into place rather than symlinked.

- `.wslconfig` — tuned for the 16 vCPU / 64 GB DevBox + heavy Claude Code
  (multiple instances + VS Code + MCP): 13 vCPUs, 48 GB, gradual memory reclaim,
  sparse VHD.
- `.wslconfig.baseline-8cpu` — backup of the previous 8 vCPU / 16 GB box config.
- `99-claude-heavy.conf` — raises inotify limits (file watchers) for VS Code + Claude.
- `reset-wsl.bat` — Windows recovery script.
- `deploy.sh` — copies `.wslconfig` + `reset-wsl.bat` to `C:\Users\<user>\` and
  installs the sysctl.

```bash
./wsl/deploy.sh   # then in Windows:  wsl --shutdown
```

## Windows Terminal (`windows-terminal/`)

Windows Terminal keeps its entire config — profiles (your bundled shells), color
schemes, keybindings — in a single `settings.json` on the Windows C: drive, so it
is **copied**, not symlinked.

- `settings.json` — versioned copy of the live Terminal config.
- `deploy.sh` — `backup` captures the live config into the repo; `restore`
  (default) writes it back to `…\LocalState\settings.json`, saving a timestamped
  `.bak` of whatever was there first.

```bash
./windows-terminal/deploy.sh backup    # capture current config -> repo
./windows-terminal/deploy.sh restore   # write repo copy -> Windows (default)
```

Caveats: install fonts (Nerd Font / Cascadia Code) separately; dynamic WSL /
PowerShell profiles re-match via their `source`, so they reappear automatically
once those shells are installed; Windows Terminal has no native cloud sync.

## Notes

- Do **not** run the macOS `~/dotfiles/install.sh` on this box — its Stow step
  would clash with the `~/.zshrc` symlink managed here.
- `~/.zshrc` is a symlink to this repo's `.zshrc`; the macOS repo no longer
  drives the shell config on this machine.
- Startup: ~0.7 s (was 5–13 s before tuning).
