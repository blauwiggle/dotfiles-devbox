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

## Notes

- Do **not** run the macOS `~/dotfiles/install.sh` on this box — its Stow step
  would clash with the `~/.zshrc` symlink managed here.
- `~/.zshrc` is a symlink to this repo's `.zshrc`; the macOS repo no longer
  drives the shell config on this machine.
- Startup: ~0.7 s (was 5–13 s before tuning).
