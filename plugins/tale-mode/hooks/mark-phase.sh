#!/usr/bin/env bash
# tale-mode — phase marker (UserPromptExpansion hook).
#
# WHAT IT DOES
#   Claude Code runs this when a slash command EXPANDS into a prompt and the command name
#   matches the hooks.json matcher ("tale-mode:kickoff-phase"). It records that a DELIBERATE
#   build phase has started in THIS session by writing a session-scoped marker:
#       <project>/.claude/tale-mode.phase.<session_id>.json
#   The Stop hook reads that marker to auto-arm the committed-config gate loop — so the
#   enforcement can't be forgotten: typing `/tale-mode:kickoff-phase` turns it on, with no
#   agent memory involved. (The committed gates still only run if the repo's `tale-mode.json`
#   hash is in your trust store — see hooks/stop-goal-loop.sh.)
#
# CONTRACT (verified live against claude 2.1.195 via a --plugin-dir smoke)
#   UserPromptExpansion stdin carries: session_id, command_name (NAMESPACED, e.g.
#   "tale-mode:kickoff-phase"), command_args, command_source, expansion_type, cwd. The
#   matcher is a regex tested against the FULL namespaced command_name (a bare "kickoff-phase"
#   does NOT match) — so hooks.json uses the namespaced name; this script re-confirms it.
#
# SAFETY
#   This hook must NEVER block or perturb the user's command. It drains stdin, suppresses
#   every error, writes nothing to stdout/stderr, and ALWAYS exits 0 (so the expansion
#   proceeds untouched — only exit 2 / a "block" decision would interrupt it). It makes no
#   network calls and reads no repo files; its only effect is writing the marker.
set -uo pipefail

INPUT=$(cat 2>/dev/null || true)

# jq is required to read the session id; without it we can't session-scope safely -> do nothing.
command -v jq >/dev/null 2>&1 || exit 0

# Defensive command guard: the hooks.json matcher already scopes us to the kickoff command,
# but re-confirm the command name so a mis-wired/over-broad matcher can't arm on the wrong
# command. Accept any plugin namespace ending in ":kickoff-phase" (the marketplace namespace
# is normally "tale-mode" but need not be relied upon literally).
CMD=$(printf '%s' "$INPUT" | jq -r '.command_name // ""' 2>/dev/null || true)
case "$CMD" in
  *:kickoff-phase|kickoff-phase) ;;
  *) exit 0 ;;
esac

# Project root: prefer CLAUDE_PROJECT_DIR (Claude Code sets it for hooks); fall back to the
# payload's cwd. The cwd fallback is acceptable here because this hook is NON-blocking and only
# writes session-scoped state — unlike the Stop gate, which must never arm against a cwd it
# doesn't control.
ROOT="${CLAUDE_PROJECT_DIR:-}"
[ -n "$ROOT" ] || ROOT=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || true)
[ -n "$ROOT" ] || exit 0

# Session-scope the marker (mirrors the goal-file in stop-goal-loop.sh): a phase armed by one
# session must never enforce against another. Validate session_id as a safe filename token
# first; empty/invalid -> do nothing (no unscoped marker — a phase is always per-session).
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)
case "$SID" in (*[!a-zA-Z0-9_-]*|'') SID="" ;; esac
[ -n "$SID" ] || exit 0

MARKER="$ROOT/.claude/tale-mode.phase.$SID.json"
# Idempotent: a re-`kickoff-phase` mid-session must NOT reset the round counter, so only
# (re)create the marker when it's absent. The Stop hook owns updates (rounds, mtime refresh).
if [ ! -f "$MARKER" ]; then
  MR="${TALE_PHASE_MAX_ROUNDS:-50}"
  case "$MR" in (''|*[!0-9]*) MR=50 ;; esac
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)
  mkdir -p "$ROOT/.claude" 2>/dev/null || true
  { jq -cn --arg s "$SID" --arg ts "$TS" --argjson mr "$MR" \
      '{session:$s, started:$ts, rounds:0, max_rounds:$mr, needs_user:null}' > "$MARKER"; } 2>/dev/null || true
fi

exit 0
