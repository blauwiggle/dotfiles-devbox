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

echo "Done. Open a new shell or run: source ~/.zshrc"
