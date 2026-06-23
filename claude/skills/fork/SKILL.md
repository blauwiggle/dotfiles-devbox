---
name: fork
model: claude-haiku-4-5-20251001
description: Fork the current Claude Code chat into a new, independent session so the user can try a side-quest interactively without losing the main thread. Hands over a ready-to-run command; the original session stays untouched. Use when the user says "fork", "fork this chat/session", "abzweigen", "side-quest", or wants a branched copy of the current conversation to experiment in.
---

# Fork the current session (`/fork`)

Goal: give the user a **ready-to-run command** that forks **this** session into a new, independent one they can chat in directly. The current session is never modified.

## How it works

- Claude Code assigns a session id (UUID) at launch and exports it as `$CLAUDE_CODE_SESSION_ID` — constant for the whole session.
- `claude --resume <id> --fork-session` resumes that session but writes to a **new** session id → the original stays untouched, the fork is fully interactive.

## Steps

1. Resolve the session id and build the command:

   ```bash
   echo "claude --resume \"$CLAUDE_CODE_SESSION_ID\" --fork-session"
   ```

   Fallback if `$CLAUDE_CODE_SESSION_ID` is empty (older Claude Code): use the most recently
   modified transcript filename (without `.jsonl`) as the id — heuristic, unreliable when several
   sessions run in parallel:

   ```bash
   ls -t ~/.claude/projects/*/*.jsonl | head -1
   ```

2. Present the resolved command in a code block so the user can paste it into a new terminal or a
   new VSCode Claude tab.

3. Also offer the no-id interactive fallback (opens the session picker, forks whatever is chosen):

   ```bash
   claude --resume --fork-session
   ```

## Rules

- **Do NOT run the forked `claude` yourself as a subprocess.** It would spawn a nested,
  non-interactive instance in the sandbox — not a usable chat. Only hand over the command; the user
  launches it.
- A skill cannot open a new interactive window — that is the terminal's / IDE's job.
- The fork reads the on-disk transcript, so the very last not-yet-flushed turn may be missing.
