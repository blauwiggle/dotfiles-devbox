#!/usr/bin/env bash
# Configure global git identity + Azure DevOps credential manager (idempotent).
# Identity from env (GIT_USER_NAME / GIT_USER_EMAIL) or interactive prompt.
# Optional: generate an ed25519 SSH key with --ssh (or SSH_KEYGEN=1).
set -euo pipefail

name="${GIT_USER_NAME:-$(git config --global user.name || true)}"
email="${GIT_USER_EMAIL:-$(git config --global user.email || true)}"
[ -z "$name" ]  && { printf "git user.name:  "; read -r name; }
[ -z "$email" ] && { printf "git user.email: "; read -r email; }
git config --global user.name  "$name"
git config --global user.email "$email"

# Resolve git-credential-manager (Homebrew install or PATH)
GCM="$(command -v git-credential-manager || true)"
[ -z "$GCM" ] && [ -x /home/linuxbrew/.linuxbrew/bin/git-credential-manager ] \
  && GCM=/home/linuxbrew/.linuxbrew/bin/git-credential-manager

if [ -n "$GCM" ]; then
  # Replace any previous (possibly messy) helper stack with a single clean entry.
  git config --global --unset-all credential.helper 2>/dev/null || true
  git config --global credential.helper "$GCM"
  # 'cache' keeps tokens in memory (re-auth after reboot). Use 'plaintext' if you
  # prefer persistence: git config --global credential.credentialStore plaintext
  git config --global credential.credentialStore cache
  echo "  [ok] credential.helper -> $GCM"
else
  echo "  [warn] git-credential-manager not found — install via Brewfile.linux first."
fi

git config --global init.defaultBranch main
git config --global pull.ff only

# Optional SSH key (HTTPS+GCM already covers ADO/GitHub; SSH is opt-in)
if [ "${1:-}" = "--ssh" ] || [ "${SSH_KEYGEN:-0}" = "1" ]; then
  if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
    ssh-keygen -t rsa -b 4096 -C "$email" -f "$HOME/.ssh/id_rsa" -N ""
    echo "  [ok] RSA 4096 key generated. Register this public key with Azure DevOps:"
    echo ""; cat "$HOME/.ssh/id_rsa.pub"; echo ""
  else
    echo "  [ok] ~/.ssh/id_rsa already exists — leaving it."
  fi
fi
echo "  [ok] git identity + Azure DevOps credential setup complete."
