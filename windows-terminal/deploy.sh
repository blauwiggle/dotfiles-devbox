#!/usr/bin/env bash
# Sync Windows Terminal settings.json between this repo and its live Windows location.
# settings.json lives on the Windows C: drive (not stow-able), so it is COPIED, not symlinked.
#   ./deploy.sh            restore (repo -> Windows; default)
#   ./deploy.sh restore    same as above
#   ./deploy.sh backup     capture the current Windows config -> repo
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve the Windows username via interop; fall back to the known profile.
WIN_USER="$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r\n ')"
if [ -z "${WIN_USER}" ] || [ ! -d "/mnt/c/Users/${WIN_USER}" ]; then
  WIN_USER="$(ls /mnt/c/Users 2>/dev/null | grep -vi public | grep -vi default | head -1)"
fi
WIN_HOME="/mnt/c/Users/${WIN_USER}"
[ -d "${WIN_HOME}" ] || { echo "ERROR: Windows home not found: ${WIN_HOME}"; exit 1; }

# settings.json location candidates, in priority order: Store, Preview, unpackaged.
WIN_LAD="${WIN_HOME}/AppData/Local"
WT_CANDIDATES=(
  "${WIN_LAD}/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
  "${WIN_LAD}/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json"
  "${WIN_LAD}/Microsoft/Windows Terminal/settings.json"
)
REPO_FILE="${DIR}/settings.json"

case "${1:-restore}" in
  backup)
    # Windows -> repo: copy the first existing live settings.json into the repo, verbatim.
    # No JSON parsing: the file is JSONC (// comments, trailing commas).
    for f in "${WT_CANDIDATES[@]}"; do
      if [ -f "${f}" ]; then
        sed "s|/Users/${WIN_USER}/|/Users/<WIN_USER>/|g" "${f}" > "${REPO_FILE}"
        echo "  [ok] backed up: ${f}"
        echo "        -> ${REPO_FILE}"
        exit 0
      fi
    done
    echo "ERROR: no Windows Terminal settings.json found. Start Windows Terminal once, then retry."
    exit 1
    ;;
  restore)
    # repo -> Windows: write the repo copy back to the live location.
    [ -f "${REPO_FILE}" ] || {
      echo "ERROR: no repo copy to restore: ${REPO_FILE}. Run './deploy.sh backup' first."
      exit 1
    }

    # Prefer a candidate whose target dir already exists.
    target=""
    for f in "${WT_CANDIDATES[@]}"; do
      if [ -d "$(dirname "${f}")" ]; then target="${f}"; break; fi
    done
    if [ -z "${target}" ]; then
      echo "ERROR: Windows Terminal config dir not found."
      echo "       Start Windows Terminal once so it creates LocalState, then retry."
      exit 1
    fi

    # Safety: timestamped backup of whatever is there now (wsl/deploy.sh overwrites blind; we don't).
    if [ -f "${target}" ]; then
      cp "${target}" "${target}.bak-$(date +%s)"
      echo "  [ok] saved current -> ${target}.bak-<ts>"
    fi
    sed "s|<WIN_USER>|${WIN_USER}|g" "${REPO_FILE}" > "${target}"
    echo "  [ok] restored: ${REPO_FILE}"
    echo "        -> ${target}"
    echo
    echo "Restart Windows Terminal to apply."
    ;;
  *)
    echo "usage: $0 [restore|backup]" >&2
    exit 2
    ;;
esac
