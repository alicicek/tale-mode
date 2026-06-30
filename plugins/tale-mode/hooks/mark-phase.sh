#!/usr/bin/env bash
# tale-mode — phase marker (UserPromptSubmit hook; cross-platform: Claude Code + Codex).
#
# WHAT IT DOES
#   Runs on every UserPromptSubmit. When the submitted prompt is a /tale-mode:kickoff-phase
#   invocation, it records that a DELIBERATE build phase has started in THIS session by writing a
#   session-scoped marker:
#       <project>/.claude/tale-mode.phase.<session_id>.json
#   The Stop hook reads that marker to auto-arm the committed-config gate loop — so the
#   enforcement can't be forgotten: running /tale-mode:kickoff-phase turns it on, with no
#   agent memory involved. (The committed gates still only run if the repo's `tale-mode.json`
#   hash is in your trust store — see hooks/stop-goal-loop.sh.)
#
# WHY UserPromptSubmit (not UserPromptExpansion)
#   UserPromptExpansion is a Claude-Code-only event; Codex's strict hook parser rejects the
#   unknown event ("unknown variant") and fails to load the WHOLE plugin's hooks. UserPromptSubmit
#   is valid on BOTH runtimes, and on Claude Code its payload carries the literal `prompt`
#   (verified live via a --plugin-dir smoke: prompt="/tale-mode:kickoff-phase <plan> <phase>"),
#   so we detect the kickoff from the prompt text. A `command_name` field (if a host provides one)
#   is also accepted, for forward/back compat.
#
# SAFETY
#   This hook must NEVER block or perturb the user's prompt. It fires on EVERY submit, so it must
#   be cheap and silent on a non-kickoff prompt. It drains stdin, suppresses every error, writes
#   nothing to stdout/stderr, and ALWAYS exits 0. It makes no network calls and reads no repo
#   files; its only effect is writing the marker on a kickoff.
set -uo pipefail

INPUT=$(cat 2>/dev/null || true)

# jq is required to read the session id; without it we can't session-scope safely -> do nothing.
command -v jq >/dev/null 2>&1 || exit 0

# Detect a kickoff-phase invocation. We run on EVERY UserPromptSubmit, so a non-kickoff prompt
# MUST fall through silently. Match either the literal `prompt` (UserPromptSubmit, both runtimes —
# e.g. "/tale-mode:kickoff-phase <plan> <phase>") or a `command_name` (if a host provides one).
# Accept any plugin namespace ending in ":kickoff-phase" (normally "tale-mode", not relied upon).
CMD=$(printf '%s' "$INPUT" | jq -r '.command_name // ""' 2>/dev/null || true)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null || true)
_hit=0
case "$CMD"    in *:kickoff-phase|kickoff-phase) _hit=1 ;; esac
case "$PROMPT" in *:kickoff-phase*)              _hit=1 ;; esac
[ "$_hit" = 1 ] || exit 0

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
  # Atomic create: write to a temp file, then rename. A direct redirect could leave an empty/
  # truncated marker if jq is interrupted mid-write — and since this hook only (re)creates when
  # the marker is ABSENT, a re-kickoff would never overwrite the corrupt file. Mirrors the
  # mktemp+mv persist pattern in stop-goal-loop.sh.
  MTMP=$(mktemp 2>/dev/null || echo "$MARKER.tmp")
  if jq -cn --arg s "$SID" --arg ts "$TS" --argjson mr "$MR" \
      '{session:$s, started:$ts, rounds:0, max_rounds:$mr, needs_user:null}' > "$MTMP" 2>/dev/null \
      && mv "$MTMP" "$MARKER" 2>/dev/null; then :; else rm -f "$MTMP" 2>/dev/null || true; fi
fi

exit 0
