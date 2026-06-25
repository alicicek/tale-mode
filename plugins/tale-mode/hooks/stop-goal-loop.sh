#!/usr/bin/env bash
# tale-mode — self-armed goal loop (Stop hook, deterministic gate).
#
# WHAT IT DOES
#   When the agent has "armed" a goal by writing  <project>/.claude/active-goal.json ,
#   this Stop hook refuses to let the turn end until that goal's `check` command
#   passes — turning "keep going until X is true" into something the AGENT can start
#   itself (by writing the file), which it cannot do with the user-only /goal command.
#
#   No goal-file  -> exit 0, silent. Normal turns are NEVER touched.
#   check passes  -> clear the file, allow the turn to end (done).
#   check fails   -> emit {"decision":"block","reason":...} so Claude Code gives the
#                    agent another turn, with the foundation-first / two-strike
#                    disciplines injected as the reason. rounds++ each time.
#   max_rounds    -> give up cleanly (clear + tell the user); never loop forever.
#
# CONTRACT (verified against code.claude.com/docs/en/hooks):
#   Stop blocks via  exit 0 + {"decision":"block","reason":"..."} on stdout; allows via
#   exit 0 with no decision. The SELF-CONTAINED safeties are (1) the per-goal `max_rounds`
#   ceiling and (2) failing OPEN (allowing the stop) on ANY inability to advance the round
#   counter. We do NOT rely on a platform block-cap: CLAUDE_CODE_STOP_HOOK_BLOCK_CAP is
#   NOT in the public hooks docs — treat it as UNVERIFIED, not a safety net. We deliberately
#   ignore `stop_hook_active` (we WANT to keep looping); max_rounds + fail-open bound it.
#
# SECURITY: `check` is ARBITRARY SHELL, run every turn from the project root with your
#   privileges, until the goal is cleared. It MUST be read-only / idempotent. Arming a goal
#   = granting recurring code-exec — only arm a check you would run yourself.
#
# This file is GENERIC — no project, vendor, or stack specifics. The only
# project-supplied input is the goal-file's `check` command.
set -uo pipefail

INPUT=$(cat 2>/dev/null || true)

# Project root MUST come from CLAUDE_PROJECT_DIR (Claude Code sets it for hooks). We do
# NOT fall back to the hook input's cwd for a BLOCKING decision: a stray/sibling
# .claude/active-goal.json under an agent-controlled cwd must never trap an unrelated turn.
ROOT="${CLAUDE_PROJECT_DIR:-}"
[ -n "$ROOT" ] || exit 0
# Session-scope the goal-file: a goal armed by one session must never trap another in the same
# repo (a crashed/previous session leaves its file; per-session keying means we only ever read
# OUR session's). session_id is a common Stop-hook input field; validate it as a safe filename
# token first. Empty/absent/invalid (or no jq) -> the legacy unsuffixed file, preserving v1.
SID=""
command -v jq >/dev/null 2>&1 && SID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)
case "$SID" in (*[!a-zA-Z0-9_-]*|'') SID="" ;; esac
if [ -n "$SID" ]; then
  GOAL_FILE="$ROOT/.claude/active-goal.$SID.json"
  LEGACY="$ROOT/.claude/active-goal.json"
  # The agent arms by writing the simple `active-goal.json` (it doesn't know its own session_id).
  # Claim it for THIS session — move it to the scoped path so only OUR session ever reads it, and
  # a goal can't trap a different session. (-f so a re-arm overwrites the prior scoped goal.)
  [ -f "$LEGACY" ] && mv -f "$LEGACY" "$GOAL_FILE" 2>/dev/null || true
  # Hygiene (only once WE have an active goal — keeps normal turns silent): reap OTHER sessions'
  # goal-files once clearly stale (a crashed session never clears its own). Never ours; never
  # within the lease window — the per-round rewrite below refreshes mtime, so a live loop
  # survives. Best-effort; the per-session key above is the real fix, not this.
  [ -f "$GOAL_FILE" ] && command -v find >/dev/null 2>&1 && find "$ROOT/.claude" -maxdepth 1 -type f \
    -name 'active-goal.*.json' ! -name "active-goal.$SID.json" -mmin +"${TALE_GOAL_TTL_MIN:-30}" -delete 2>/dev/null
else
  GOAL_FILE="$ROOT/.claude/active-goal.json"
fi

# No active goal -> never interfere with a normal turn.
[ -f "$GOAL_FILE" ] || exit 0
# jq is required; if it's missing, fail OPEN (let the turn end) rather than trap.
command -v jq >/dev/null 2>&1 || exit 0

GOAL=$(jq -r '.goal // ""'        "$GOAL_FILE" 2>/dev/null || true)
CHECK=$(jq -r '.check // ""'      "$GOAL_FILE" 2>/dev/null || true)
ROUNDS=$(jq -r '.rounds // 0'     "$GOAL_FILE" 2>/dev/null || echo 0)
MAX=$(jq -r '.max_rounds // 25'   "$GOAL_FILE" 2>/dev/null || echo 25)
NEEDS_USER=$(jq -r '.needs_user // ""' "$GOAL_FILE" 2>/dev/null || true)
case "$ROUNDS" in (*[!0-9]*|'') ROUNDS=0 ;; esac
case "$MAX"    in (*[!0-9]*|'') MAX=25 ;; esac

# No USABLE check (empty OR whitespace/blank-only) -> disarm + allow. A blank check would
# otherwise run as a shell no-op (RC 0) and report a FALSE "goal met", silently disarming.
if [ -z "${CHECK//[[:space:]]/}" ]; then
  rm -f "$GOAL_FILE"
  jq -n '{systemMessage:"tale-mode: goal had no usable check — disarmed."}'
  exit 0
fi

# Paused for a genuine human dependency: the agent set `needs_user` (a secret it can't
# hold, a dashboard only the user sees, an interactive login, an outward-facing action).
# Allow the turn to end so it can ASK. The agent clears needs_user (-> null) next turn to
# resume the loop. Without this, a still-failing check would trap it from ever pausing.
if [ -n "$NEEDS_USER" ] && [ "$NEEDS_USER" != "null" ]; then exit 0; fi

# Hard ceiling -> give up cleanly. The agent can re-arm if it judges it worthwhile.
if [ "$ROUNDS" -ge "$MAX" ]; then
  rm -f "$GOAL_FILE"
  jq -n --arg g "$GOAL" --arg n "$ROUNDS" \
    '{systemMessage: ("tale-mode goal loop: hit max_rounds (" + $n + ") without meeting — " + $g + ". Stopped; re-arm or take over.")}'
  exit 0
fi

# Run the deterministic check from the project root, under a timeout when available
# (stock macOS lacks `timeout` -> run without). exit 0 == goal met.
TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout ${TALE_CHECK_TIMEOUT:-120}"
OUT=$( cd "$ROOT" 2>/dev/null && $TO bash -c "$CHECK" 2>&1 ); RC=$?
TAIL=$(printf '%s' "$OUT" | tail -c 1200)

if [ "$RC" -eq 0 ]; then
  rm -f "$GOAL_FILE"
  jq -n --arg g "$GOAL" '{systemMessage: ("tale-mode goal met ✓ — " + $g)}'
  exit 0
fi

# Not met -> advance the round counter. CRITICAL (fail-open): if we cannot PERSIST the
# increment (read-only/locked .claude, full disk), ALLOW the stop instead of blocking — a
# frozen counter would never reach max_rounds and would trap the session forever.
NEXT=$((ROUNDS + 1))
TMP=$(mktemp 2>/dev/null || echo "$GOAL_FILE.tmp")
if jq --argjson r "$NEXT" '.rounds=$r' "$GOAL_FILE" > "$TMP" 2>/dev/null && mv "$TMP" "$GOAL_FILE" 2>/dev/null; then
  :
else
  rm -f "$TMP" 2>/dev/null
  jq -n '{systemMessage:"tale-mode: cannot persist goal rounds (read-only/locked dir) — stopping to avoid an unbounded loop."}'
  exit 0
fi

REASON=$(printf 'Goal NOT met (round %s/%s): %s

Check `%s` exited %s. Last output:
%s

Keep going. Foundation-first: confirm the artifact EXISTS and the environment is CAPABLE before fixing symptoms — one existence check often collapses the search. Two-strike: if two fixes in a row failed, STOP and re-verify the foundational assumption instead of trying a third. Drive the diagnostics yourself; only pause for something that genuinely needs the user. If this goal is truly unreachable, delete .claude/active-goal.json and explain why — do not band-aid the check to make it pass.' \
  "$NEXT" "$MAX" "$GOAL" "$CHECK" "$RC" "$TAIL")

jq -n --arg r "$REASON" '{decision:"block", reason:$r}'
exit 0
