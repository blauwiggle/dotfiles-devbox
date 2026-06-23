#!/usr/bin/env node
/**
 * ADO compact nudge (count signal).
 *
 * Emits a /compact suggestion every N Azure DevOps MCP calls in a session.
 * Pairs with ECC's suggest-compact.js (context-size signal) on the same
 * PreToolUse matcher — this script owns only the cheap call-count floor,
 * scoped to ADO so it never nudges during ordinary editing.
 *
 * Output: hookSpecificOutput.additionalContext on stdout so the suggestion
 * reaches the model. Always exits 0 (never blocks the tool call).
 *
 * Tunable: ADO_COMPACT_COUNT_INTERVAL (default 3).
 */

const fs = require('fs');
const os = require('os');
const path = require('path');

const INTERVAL = Math.max(
  1,
  parseInt(process.env.ADO_COMPACT_COUNT_INTERVAL || '3', 10) || 3
);

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function resolveSessionId() {
  try {
    const input = JSON.parse(readStdin() || '{}');
    if (input && typeof input.session_id === 'string' && input.session_id) {
      return input.session_id.replace(/[^a-zA-Z0-9_-]/g, '') || 'default';
    }
  } catch {
    /* fall through */
  }
  return (process.env.CLAUDE_SESSION_ID || 'default').replace(/[^a-zA-Z0-9_-]/g, '') || 'default';
}

function main() {
  const sessionId = resolveSessionId();
  const counterFile = path.join(os.tmpdir(), `ado-compact-count-${sessionId}`);

  let count = 0;
  try {
    const parsed = parseInt(fs.readFileSync(counterFile, 'utf8').trim(), 10);
    if (Number.isInteger(parsed) && parsed > 0 && parsed <= 1000000) count = parsed;
  } catch {
    /* first call this session */
  }
  count += 1;
  try {
    fs.writeFileSync(counterFile, String(count));
  } catch {
    /* non-fatal; nudge cadence may slip but never blocks */
  }

  if (count % INTERVAL === 0) {
    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: 'PreToolUse',
          additionalContext: `[ADO] ${count} Azure DevOps MCP calls this session — suggest /compact to the user at the next logical boundary if context is getting heavy.`
        }
      })
    );
  }

  process.exit(0);
}

main();
