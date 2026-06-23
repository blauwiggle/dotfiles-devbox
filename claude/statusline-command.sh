#!/usr/bin/env bash
input=$(cat)

cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Shorten home directory to ~
home="$HOME"
cwd="${cwd/#$home/\~}"

parts=()

[ -n "$cwd" ] && parts+=("$cwd")
[ -n "$model" ] && parts+=("$model")
[ -n "$used" ] && parts+=("ctx:$(printf '%.0f' "$used")%")

printf '%s' "$(IFS=' | '; echo "${parts[*]}")"
