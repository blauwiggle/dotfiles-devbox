#!/usr/bin/env bash
# DevBox/WSL bootstrap: Homebrew + zinit + Brewfile + zsh + WSL/Terminal config,
# git identity + Azure DevOps credential manager, and Claude Code config restore.
# Runs under bash — no zsh/.zshrc needed to bootstrap; it installs zsh and writes ~/.zshrc.
# Idempotent. Separate from the private macOS dotfiles repo so the two never clash.
#   ./install.sh           full bootstrap
#   ./install.sh --check    read-only prerequisite report, then exit
# Flags:  SKIP_GIT=1  SKIP_CLAUDE=1  MAKE_ZSH_DEFAULT=1  SSH_KEYGEN=1
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${1:-}" = "--check" ]; then exec "$DIR/prereq-check.sh"; fi

# Homebrew (linuxbrew) - install if missing. On Debian/Ubuntu it needs these apt
# packages first; the installer is interactive and needs sudo. Best-effort.
if ! command -v brew >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    echo "Installing Homebrew prerequisites via apt (sudo password may be requested)..."
    sudo apt-get update -y && sudo apt-get install -y build-essential procps curl file git zsh \
      || echo "  [warn] apt prerequisites failed - install build-essential procps curl file git zsh manually"
  fi
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# Make brew available in future bash/login shells too (zsh loads it via .zshrc).
PROFILE="$HOME/.profile"
SHELLENV_LINE='eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'
if [ -d /home/linuxbrew/.linuxbrew ] && ! grep -qF "$SHELLENV_LINE" "$PROFILE" 2>/dev/null; then
  printf '\n# Homebrew\n%s\n' "$SHELLENV_LINE" >> "$PROFILE"
  echo "  [ok] added brew shellenv to ~/.profile"
fi

# zinit (plugin manager)
bash -c "$(curl --fail --show-error --silent --location \
  https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"

# CLI tools
brew bundle --file="$DIR/Brewfile.linux"

# Symlink zsh config (creates ~/.zshrc, so zsh never shows the new-user wizard)
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

# Optionally make zsh the default login shell (opt-in). MAKE_ZSH_DEFAULT=1 or prompt.
ZSH_BIN="$(command -v zsh || true)"
if [ -n "$ZSH_BIN" ] && [ "$(basename "${SHELL:-}")" != "zsh" ]; then
  do_chsh="${MAKE_ZSH_DEFAULT:-}"
  if [ -z "$do_chsh" ] && [ -t 0 ]; then
    printf "Make zsh your default login shell now? [y/N] "; read -r ans
    case "$ans" in [Yy]*) do_chsh=1 ;; esac
  fi
  if [ "$do_chsh" = "1" ]; then
    grep -qxF "$ZSH_BIN" /etc/shells 2>/dev/null || echo "$ZSH_BIN" | sudo tee -a /etc/shells >/dev/null || true
    chsh -s "$ZSH_BIN" && echo "  [ok] default shell -> $ZSH_BIN (log out/in to apply)" \
      || echo "  [warn] chsh failed - run: chsh -s \"$ZSH_BIN\""
  fi
fi

echo "Done. Open a new shell or run: source ~/.zshrc"
echo "Next: run 'claude' to authenticate; migrate old conversations with ./migrate/backup-conversations.sh on the old box."
