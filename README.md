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

## Notes

- Do **not** run the macOS `~/dotfiles/install.sh` on this box — its Stow step
  would clash with the `~/.zshrc` symlink managed here.
- `~/.zshrc` is a symlink to this repo's `.zshrc`; the macOS repo no longer
  drives the shell config on this machine.
- Startup: ~0.7 s (was 5–13 s before tuning).
