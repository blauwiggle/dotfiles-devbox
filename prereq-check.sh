#!/usr/bin/env bash
# Read-only prerequisite check for a fresh box. Lists missing tools; changes nothing.
set -uo pipefail
need=(brew git gh node npm az claude git-credential-manager jq curl ssh zsh)
missing=()
echo "Prerequisite check:"
for t in "${need[@]}"; do
  if command -v "$t" >/dev/null 2>&1; then printf "  [ ok ] %s\n" "$t"
  else printf "  [MISS] %s\n" "$t"; missing+=("$t"); fi
done
if [ ${#missing[@]} -gt 0 ]; then
  echo; echo "Missing: ${missing[*]}"
  echo "Run ./install.sh to install everything via Homebrew (Brewfile.linux)."
  exit 1
fi
echo; echo "All prerequisites present."
