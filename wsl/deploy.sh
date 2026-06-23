#!/usr/bin/env bash
# Deploy WSL config from this repo to its live locations.
# .wslconfig lives on the Windows C: drive (not stow-able), so it is COPIED, not symlinked.
# After running, in Windows PowerShell/CMD:  wsl --shutdown
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve the Windows username via interop; fall back to the known profile.
WIN_USER="$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r\n ')"
if [ -z "${WIN_USER}" ] || [ ! -d "/mnt/c/Users/${WIN_USER}" ]; then
  WIN_USER="vanhee"
fi
WIN_HOME="/mnt/c/Users/${WIN_USER}"
[ -d "${WIN_HOME}" ] || { echo "ERROR: Windows home not found: ${WIN_HOME}"; exit 1; }

echo "Deploying to Windows home: ${WIN_HOME}"
cp "${DIR}/.wslconfig"    "${WIN_HOME}/.wslconfig"
cp "${DIR}/reset-wsl.bat" "${WIN_HOME}/reset-wsl.bat"
echo "  [ok] .wslconfig + reset-wsl.bat copied"

# Linux-side sysctl (needs root)
if sudo -n true 2>/dev/null || [ -w /etc/sysctl.d ]; then
  sudo cp "${DIR}/99-claude-heavy.conf" /etc/sysctl.d/99-claude-heavy.conf
  sudo sysctl --system >/dev/null 2>&1 || true
  echo "  [ok] /etc/sysctl.d/99-claude-heavy.conf installed"
else
  echo "  [skip] sysctl (no sudo). Apply later with:"
  echo "         sudo cp \"${DIR}/99-claude-heavy.conf\" /etc/sysctl.d/ && sudo sysctl --system"
fi

echo
echo "Next: run in Windows PowerShell/CMD ->  wsl --shutdown"
echo "Then verify:  nproc (expect 13)  |  free -g (expect ~48)  |  cat /proc/sys/fs/inotify/max_user_watches (expect 524288)"
