#!/usr/bin/env bash
# DevBox/WSL bootstrap: Homebrew + zinit + Brewfile + zsh + WSL/Terminal config,
# git identity + Azure DevOps credential manager, and Claude Code config restore.
# Idempotent. Separate from the private macOS dotfiles repo so the two never clash.
#   ./install.sh           full bootstrap
#   ./install.sh --check    read-only prerequisite report, then exit
# Skip flags:  SKIP_GIT=1  SKIP_CLAUDE=1   Optional:  SSH_KEYGEN=1 (generate ed25519)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${1:-}" = "--check" ]; then exec "$DIR/prereq-check.sh"; fi

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

# Git identity + Azure DevOps credential manager (SKIP_GIT=1 to skip)
if [ "${SKIP_GIT:-0}" != "1" ]; then
  "$DIR/git/bootstrap-git.sh" || echo "  [warn] git bootstrap skipped/failed - run ./git/bootstrap-git.sh manually"
fi

# Claude Code config restore (SKIP_CLAUDE=1 to skip)
if [ "${SKIP_CLAUDE:-0}" != "1" ]; then
  "$DIR/claude/restore.sh" || echo "  [warn] claude restore skipped/failed - run ./claude/restore.sh manually"
fi

# WSL only: deploy Windows-side .wslconfig + Linux sysctl, restore Windows Terminal.
if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  echo "WSL detected -> deploying WSL config..."
  "$DIR/wsl/deploy.sh" || echo "  [warn] WSL deploy skipped/failed - run ./wsl/deploy.sh manually"
  if [ -f "$DIR/windows-terminal/settings.json" ]; then
    echo "Restoring Windows Terminal settings..."
    "$DIR/windows-terminal/deploy.sh" \
      || echo "  [warn] Windows Terminal restore skipped/failed - run ./windows-terminal/deploy.sh manually"
  fi
fi

echo "Done. Open a new shell or run: source ~/.zshrc"
echo "Next: run 'claude' to authenticate; migrate old conversations with ./migrate/backup-conversations.sh on the old box."
