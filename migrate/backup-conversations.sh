#!/usr/bin/env bash
# Back up Claude Code conversations/sessions OUT-OF-BAND (never into the repo).
# Produces a tarball to copy to the new box. Excludes credentials.
# Restore on the NEW box (same username + path!):  tar xzf <file> -C ~/.claude
set -euo pipefail
SRC="$HOME/.claude"
OUT="${1:-$HOME/claude-conversations-$(date +%Y%m%d).tar.gz}"
parts=(); for p in projects session-data todos; do [ -e "$SRC/$p" ] && parts+=("$p"); done
tar czf "$OUT" -C "$SRC" --exclude='.credentials.json' "${parts[@]}"
echo "Wrote $OUT ($(du -h "$OUT" | cut -f1))"
echo "On the NEW box (user 'michi', path /home/michi/dev): tar xzf '$OUT' -C ~/.claude"
