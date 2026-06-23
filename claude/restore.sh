#!/usr/bin/env bash
# Restore Claude Code config from this repo into ~/.claude and reinstall plugins.
# Does NOT touch ~/.claude/.credentials.json — run `claude` and log in to re-auth.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="$HOME/.claude"
mkdir -p "$CLAUDE_HOME"

for item in settings.json statusline-command.sh hooks scripts skills rules ecc; do
  [ -e "$DIR/$item" ] && cp -r "$DIR/$item" "$CLAUDE_HOME/" && echo "  + $item"
done
chmod +x "$CLAUDE_HOME/statusline-command.sh" 2>/dev/null || true

# Reinstall plugins from the manifest (best-effort; requires `claude` on PATH)
if command -v claude >/dev/null 2>&1 && [ -f "$DIR/plugins.manifest" ]; then
  grep '^marketplace' "$DIR/plugins.manifest" | while IFS=$'\t' read -r _ mname msrc; do
    [ -n "${msrc:-}" ] && claude plugin marketplace add "$msrc" 2>/dev/null \
      && echo "  marketplace + $mname" || true
  done
  grep '^plugin' "$DIR/plugins.manifest" | while IFS=$'\t' read -r _ pname enabled; do
    [ "$enabled" = "true" ] && claude plugin install "$pname" 2>/dev/null \
      && echo "  plugin + $pname" || true
  done
fi
echo "  [ok] Claude config restored. Now run 'claude' and authenticate on this machine."
