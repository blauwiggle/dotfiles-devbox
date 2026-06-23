#!/usr/bin/env bash
# DevBox/WSL zsh profile installer.
# Separate from the private macOS dotfiles repo so the two never overwrite each other.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Homebrew (linuxbrew) - install if missing
if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# zinit (plugin manager)
bash -c "$(curl --fail --show-error --silent --location \
  https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"

# CLI tools
brew bundle --file="$DIR/Brewfile.linux"

# Symlink zsh config (overwrites any existing ~/.zshrc symlink)
ln -sfn "$DIR/.zshrc" "$HOME/.zshrc"

# WSL only: deploy Windows-side .wslconfig + Linux sysctl (reuses wsl/deploy.sh).
# Skipped on non-WSL Linux. Non-fatal so a hiccup never aborts the installer.
if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  echo "WSL detected -> deploying WSL config..."
  "$DIR/wsl/deploy.sh" || echo "  [warn] WSL deploy skipped/failed - run ./wsl/deploy.sh manually"

  # Restore Windows Terminal settings, but only once a config has been captured
  # into the repo (via ./windows-terminal/deploy.sh backup). Also non-fatal.
  if [ -f "$DIR/windows-terminal/settings.json" ]; then
    echo "Restoring Windows Terminal settings..."
    "$DIR/windows-terminal/deploy.sh" \
      || echo "  [warn] Windows Terminal restore skipped/failed - run ./windows-terminal/deploy.sh manually"
  fi
fi

echo "Done. Open a new shell or run: source ~/.zshrc"
