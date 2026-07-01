#!/usr/bin/env bash
# tale-mode-governor — Codex Layer-2 governor (Stop hook, type:command).
#
# WHAT IT DOES
#   The Claude Code governor is a `type:"agent"` Stop hook (a read-only Sonnet reviewer) — but
#   Codex skips agent hooks ("agent hooks are not supported yet"). This script is the Codex
#   counterpart: once the L1 goal loop is STUCK (rounds >= 2 on this session's goal-file), it
#   spawns ONE hermetic `codex exec --sandbox read-only --ephemeral` reviewer over the goal/plan/
#   code with a fresh adversarial frame, and surfaces its single concrete finding as an ADVISORY
#   {"systemMessage": ...}. It never blocks and never allows — Layer 1 owns the decision; this
#   only breaks the anchor. (Advisory-by-design: multi-Stop-hook DECISION aggregation is
#   undocumented on both runtimes, so this hook stays off the decision channel entirely.)
#
# RECURSION GUARD (probe-proven 2026-07-01, live codex exec):
#   Hooks DO fire inside `codex exec`, and a child codex inherits this user's persisted hook
#   trust — an unguarded spawn here would re-enter this very hook, forever. The guard is the
#   TALE_GOVERNOR_ACTIVE sentinel: hook subprocesses inherit their codex process's env, and we
#   export the sentinel to the child, so the child's copy of THIS hook sees it and exits at the
#   first line. Proven live: an env var exported to `codex exec` reached that session's hook
#   subprocess env. Belt: --ephemeral keeps the child from persisting session state.
#
# PLATFORM GATE (probe-proven): runs ONLY where it applies —
#   - CLAUDE_PROJECT_DIR set  -> Claude Code -> exit (the type:agent Sonnet governor covers CC).
#   - PLUGIN_ROOT unset       -> not a Codex plugin-hook host -> exit. (Un-prefixed PLUGIN_ROOT
#     is a Codex-specific extension; verified present in live Codex plugin-hook env, and never
#     documented for Claude Code. Never detect via CODEX_HOME or CLAUDE_* — both false-signal.)
#
# SECURITY
#   Read-only by OS enforcement, not by convention: the child runs under `--sandbox read-only`
#   (Seatbelt / seccomp+bubblewrap), which overrides any config.toml sandbox_mode — proven live:
#   a `touch /tmp/...` inside the child failed "Operation not permitted", and the child could not
#   even delete the goal-file. Root resolution requires the SAME user opt-in as the L1 loop
#   (~/.tale-mode-allow-cwd-root or TALE_ALLOW_CWD_ROOT=1) — no opt-in, no root, no spawn. The
#   spawn costs one bounded model call and happens only when the loop is already stuck.
#   This hook NEVER emits a decision, always exits 0, and fails silent on every error.
set -uo pipefail

# 1. Recursion sentinel — we ARE the child's hook: do nothing, instantly.
[ -n "${TALE_GOVERNOR_ACTIVE:-}" ] && exit 0

# 2. Platform gate (see header). Kill switch: TALE_CODEX_GOVERNOR=0 disables cleanly.
[ -n "${CLAUDE_PROJECT_DIR:-}" ] && exit 0
[ -z "${PLUGIN_ROOT:-}" ] && exit 0
[ "${TALE_CODEX_GOVERNOR:-1}" = "0" ] && exit 0

# 3. Tooling + input. jq and codex are required; missing -> silent no-op (never perturb a turn).
command -v jq >/dev/null 2>&1 || exit 0
command -v codex >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null || true)

# 4. Project root — SAME trust rule as the L1 loop: stdin cwd only under the explicit user
#    opt-in, absolute + existing only. No opt-in -> inert (consistent consent boundary).
{ [ "${TALE_ALLOW_CWD_ROOT:-}" = "1" ] || [ -f "${HOME:-}/.tale-mode-allow-cwd-root" ]; } || exit 0
ROOT=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || true)
case "$ROOT" in
  /*) [ -d "$ROOT" ] || exit 0 ;;
  *)  exit 0 ;;
esac

# 5. This session's goal-file (mirror the L1 scoping: scoped first, legacy fallback).
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)
case "$SID" in (*[!a-zA-Z0-9_-]*|'') SID="" ;; esac   # empty case explicit, to match L1 (stop-goal-loop.sh)
GF=""
[ -n "$SID" ] && [ -f "$ROOT/.claude/active-goal.$SID.json" ] && GF="$ROOT/.claude/active-goal.$SID.json"
[ -z "$GF" ] && [ -f "$ROOT/.claude/active-goal.json" ] && GF="$ROOT/.claude/active-goal.json"
[ -n "$GF" ] || exit 0

# 6. Intervene ONCE per stuck goal — exactly when rounds hits 2 (the two-strike moment). L1
#    increments rounds every failing turn, so ">= 2" would spawn a full synchronous codex exec on
#    EVERY round from 2 to max_rounds; "== 2" costs exactly one reviewer call per goal (a re-armed
#    goal resets rounds -> a genuinely new stall gets a fresh review). L1 handles everything else.
GOAL=$(jq -r '.goal // ""' "$GF" 2>/dev/null || true)
CHECK=$(jq -r '.check // ""' "$GF" 2>/dev/null || true)
R=$(jq -r '.rounds // 0' "$GF" 2>/dev/null || echo 0)
case "$R" in (*[!0-9]*|'') R=0 ;; esac
[ "$((10#$R))" -eq 2 ] || exit 0

# 7. Spawn ONE read-only, ephemeral, sentinel-guarded reviewer. Hard-bounded: `timeout` when
#    available (default 90s, tune TALE_GOVERNOR_TIMEOUT) under the hooks.json timeout as belt.
OUTF=$(mktemp 2>/dev/null) || exit 0
TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout ${TALE_GOVERNOR_TIMEOUT:-90}"
PROMPT="You are a FRESH-CONTEXT adversarial reviewer for a stuck autonomous goal loop. You have READ-ONLY filesystem access; run nothing destructive. The agent in this repo has FAILED the same goal $R times: goal: ${GOAL}; check command: ${CHECK}. As a skeptic, find the ONE concrete thing it is missing, using reads only: does the FOUNDATION it assumes exist (files/wiring present)? does a plan/spec/*.md document a CONSTRAINT it is violating (deferred/blocked/env-only)? did a recent change turn into a BAND-AID that weakens a check instead of fixing the cause? Reply with EXACTLY ONE actionable sentence naming the concrete problem and where you saw it. If you find nothing concrete, reply exactly: NOTHING"
TALE_GOVERNOR_ACTIVE=1 $TO codex exec --skip-git-repo-check --ephemeral -s read-only \
  -C "$ROOT" -o "$OUTF" "$PROMPT" >/dev/null 2>&1 || true

# head (not tail): the prompt asks for one sentence, but on a non-compliant "finding then
# elaboration" reply, keeping the FIRST 600 bytes preserves the actual finding; tail would clip its start.
FINDING=$(tr -d '\r' < "$OUTF" 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | head -c 600)
rm -f "$OUTF" 2>/dev/null || true

# 8. Advisory only. Empty / NOTHING / noise -> stay silent; a concrete finding -> systemMessage
#    (renders on Codex — verified live). Never a decision; L1 keeps owning the block.
[ -n "$FINDING" ] || exit 0
case "$FINDING" in NOTHING|nothing|Nothing*) exit 0 ;; esac
jq -n --arg f "$FINDING" '{systemMessage: ("tale-mode governor (fresh-eyes, read-only): " + $f)}'
exit 0
