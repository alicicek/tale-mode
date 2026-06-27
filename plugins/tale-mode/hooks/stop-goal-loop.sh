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
#   OBSERVABILITY: on each round where the `check` actually runs, append one JSONL verdict
#   line (ts, session, goal, round, check, verdict, rc, output tail) to <project>/.claude/
#   tale-mode.log — a durable, local, cross-session audit trail. Pure side-effect, fully
#   fail-open (never affects the decision), no network. Disable with TALE_VERDICT_LOG=/dev/null.
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
# Force base-10: jq emits "08"/"09" if the goal-file carries a STRING "rounds" — all-digits, so it
# passes the sanitizer above, but a later $((08+1)) would abort as an invalid octal literal (no
# decision emitted, goal-file orphaned). 10# makes it decimal. (Sanitizer guarantees non-empty
# digits, so this never errors.) Behavior is identical for every normal integer value.
ROUNDS=$((10#$ROUNDS)); MAX=$((10#$MAX))

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

# --- Phase B: per-round verdict audit log — pure side-effect, MUST NOT affect the decision ---
# Reached only on the check-execution path (past the no-ROOT / no-goal / no-jq early-exits above),
# so RC, TAIL, ROUNDS, GOAL, CHECK, SID are all in scope. The decision below reads the STORED $RC
# (not $?), so nothing here can perturb it. The { } group routes BOTH jq's stderr AND any
# redirect-OPEN failure (read-only/locked .claude) to /dev/null *before* the >> is attempted;
# then || true -> fully fail-open + silent. jq is guaranteed present (the hook exits-open above
# otherwise). Durable cross-session audit (JSONL, one object/line); disable TALE_VERDICT_LOG=/dev/null.
LOG="${TALE_VERDICT_LOG:-$ROOT/.claude/tale-mode.log}"
# Never let the audit log resolve to a process file descriptor — the hook's own stdout/stderr, or
# ANY /dev/fd or /proc/<pid>/fd entry (incl. leading-zero forms like /dev/fd/01, which macOS still
# resolves to fd1) — writing the verdict line there could interleave with the {"decision":...}
# object on stdout. Collapse repeated/trailing slashes first so //dev/stdout, /dev/fd//1 etc. can't
# slip past, then send ANY fd-device target to /dev/null. A real file path or /dev/null is unaffected.
_lognorm=$(printf '%s' "$LOG" | tr -s '/'); _lognorm="${_lognorm%/}"
case "$_lognorm" in
  /dev/stdout|/dev/stderr|/dev/fd/*|/proc/self/fd/*|/proc/[0-9]*/fd/*) LOG=/dev/null ;;
esac
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)
{ jq -cn --arg ts "$TS" --arg sid "$SID" --arg goal "$GOAL" --argjson round "$((ROUNDS+1))" \
         --arg check "$CHECK" --argjson rc "$RC" --arg tail "$TAIL" \
   '{ts:$ts,session:$sid,goal:$goal,round:$round,check:$check,verdict:(if $rc==0 then "pass" else "fail" end),rc:$rc,tail:$tail}' \
   >> "$LOG"; } 2>/dev/null || true
# --- end Phase B audit log ---

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
