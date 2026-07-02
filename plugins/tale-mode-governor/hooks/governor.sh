#!/usr/bin/env bash
# tale-mode-governor — the unified Layer-2 governor (Stop hook, type:command, both hosts).
#
# WHAT IT DOES
#   Once the L1 goal loop is STUCK — this session's goal-file has failed exactly 2 rounds —
#   spawn ONE read-only, fresh-context reviewer over the goal/plan/code with an adversarial
#   frame, and surface its single concrete finding as an ADVISORY {"systemMessage": ...}.
#   It never blocks and never allows — Layer 1 owns the decision; this only breaks the anchor.
#
# WHY A COMMAND HOOK ON BOTH HOSTS (v2 — replaces the old type:"agent" Sonnet hook)
#   The v1 CC governor was a type:"agent" hook, so the harness spawned a Sonnet call at EVERY
#   turn-end just to discover "nothing is stuck" — the model call WAS the check. v2 inverts it:
#   this bash gate answers "stuck?" in milliseconds for free, and a model is spawned only at the
#   two-strike moment, once per goal. Idle cost: zero tokens. Escalation binary per host:
#     Claude Code -> `claude -p` pinned to a small model, --tools restricted to Read/Grep/Glob
#     Codex       -> `codex exec --sandbox read-only --ephemeral`  (OS-enforced read-only)
#   Both draw from the user's own subscription/plan for that host.
#
# RECURSION GUARD (probe-proven on Codex 2026-07-01; same mechanism on CC):
#   Hooks fire inside headless children (`codex exec` proven live; `claude -p` observed in this
#   repo's own smokes), and a child inherits the parent's plugins/trust — an unguarded spawn
#   would re-enter this very hook. The guard is the TALE_GOVERNOR_ACTIVE sentinel: hook
#   subprocesses inherit their host process env, we export the sentinel to the child, so the
#   child's copy of THIS hook (and tale-mode's L1 loop, which carries the same guard) exits at
#   the first line. Belt: --ephemeral on Codex / bounded timeout on both.
#
# PLATFORM & ROOT
#   Claude Code: CLAUDE_PROJECT_DIR is set for hooks — the TRUSTED root; no opt-in needed.
#   Codex: no CLAUDE_PROJECT_DIR; root comes from the payload cwd ONLY under the same user
#   opt-in the L1 loop uses (~/.tale-mode-allow-cwd-root or TALE_ALLOW_CWD_ROOT=1). Detect
#   Codex via un-prefixed PLUGIN_ROOT (a Codex-specific extension; never CODEX_HOME/CLAUDE_*).
#
# SECURITY
#   Read-only children: on Codex by OS sandbox (`-s read-only`, proven unable to write /tmp);
#   on Claude Code by tool restriction — `--tools Read Grep Glob` limits the BUILT-INS to three
#   non-executing tools, and `--strict-mcp-config` (with no --mcp-config) strips every MCP server,
#   so nothing write-capable or external is offered at all. The reviewer's output is escaped
#   through jq --arg into a systemMessage — it can never smuggle a decision. This hook NEVER
#   emits a decision, always exits 0, and fails silent on every error.
#
# KNOBS  TALE_GOVERNOR=0 (kill switch, both hosts; TALE_CODEX_GOVERNOR=0 still honored)
#        TALE_GOVERNOR_MODEL (CC reviewer model, default claude-sonnet-4-6)
#        TALE_GOVERNOR_TIMEOUT (seconds, default 90; the hooks.json 120s cap is the belt)
set -uo pipefail

# 1. Recursion sentinel — we ARE a child's hook: do nothing, instantly.
[ -n "${TALE_GOVERNOR_ACTIVE:-}" ] && exit 0

# 2. Kill switches (unified + the v1 Codex-era name for back-compat).
[ "${TALE_GOVERNOR:-1}" = "0" ] && exit 0
[ "${TALE_CODEX_GOVERNOR:-1}" = "0" ] && exit 0

# 3. Platform + tooling. jq is required everywhere; the escalation binary per host.
command -v jq >/dev/null 2>&1 || exit 0
HOST=""
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  HOST=cc;    command -v claude >/dev/null 2>&1 || exit 0
elif [ -n "${PLUGIN_ROOT:-}" ]; then
  HOST=codex; command -v codex  >/dev/null 2>&1 || exit 0
else
  exit 0   # neither host signature -> not a supported runtime
fi
INPUT=$(cat 2>/dev/null || true)

# 4. Project root. CC: the trusted env var. Codex: payload cwd, gated on the SAME explicit
#    user opt-in as the L1 loop, absolute + existing only (no opt-in -> inert).
if [ "$HOST" = cc ]; then
  ROOT="$CLAUDE_PROJECT_DIR"
else
  { [ "${TALE_ALLOW_CWD_ROOT:-}" = "1" ] || [ -f "${HOME:-}/.tale-mode-allow-cwd-root" ]; } || exit 0
  ROOT=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || true)
  case "$ROOT" in
    /*) [ -d "$ROOT" ] || exit 0 ;;
    *)  exit 0 ;;
  esac
fi

# 5. This session's goal-file (mirror the L1 scoping: scoped first, legacy fallback).
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)
case "$SID" in (*[!a-zA-Z0-9_-]*|'') SID="" ;; esac   # empty case explicit, to match L1
GF=""
[ -n "$SID" ] && [ -f "$ROOT/.claude/active-goal.$SID.json" ] && GF="$ROOT/.claude/active-goal.$SID.json"
[ -z "$GF" ] && [ -f "$ROOT/.claude/active-goal.json" ] && GF="$ROOT/.claude/active-goal.json"
[ -n "$GF" ] || exit 0

# 6. Intervene ONCE per stuck goal — exactly when rounds hits 2 (the two-strike moment). L1
#    increments rounds every failing turn, so ">= 2" would spawn a full model call on EVERY
#    round to max_rounds; "== 2" costs exactly one reviewer per goal (a re-armed goal resets
#    rounds -> a genuinely new stall gets a fresh review). L1 handles everything else.
GOAL=$(jq -r '.goal // ""' "$GF" 2>/dev/null || true)
CHECK=$(jq -r '.check // ""' "$GF" 2>/dev/null || true)
R=$(jq -r '.rounds // 0' "$GF" 2>/dev/null || echo 0)
case "$R" in (*[!0-9]*|'') R=0 ;; esac
[ "$((10#$R))" -eq 2 ] || exit 0

# 7. Spawn ONE read-only, sentinel-guarded reviewer, hard-bounded by `timeout` when available
#    (stock macOS lacks it -> the hooks.json 120s cap is the belt).
TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout ${TALE_GOVERNOR_TIMEOUT:-90}"
PROMPT="You are a FRESH-CONTEXT adversarial reviewer for a stuck autonomous goal loop. You have READ-ONLY access; run nothing destructive. The agent in this repo has FAILED the same goal $R times: goal: ${GOAL}; check command: ${CHECK}. As a skeptic, find the ONE concrete thing it is missing, using reads only: does the FOUNDATION it assumes exist (files/wiring present)? does a plan/spec/*.md document a CONSTRAINT it is violating (deferred/blocked/env-only)? did a recent change turn into a BAND-AID that weakens a check instead of fixing the cause? Reply with EXACTLY ONE actionable sentence naming the concrete problem and where you saw it. If you find nothing concrete, reply exactly: NOTHING"

FINDING=""
if [ "$HOST" = cc ]; then
  # Prompt via stdin: the variadic --tools list would otherwise swallow a positional prompt.
  # --tools restricts the BUILT-IN set to three non-executing tools; --strict-mcp-config with no
  # --mcp-config strips ALL MCP servers from the child, so no external/write-capable tool is even
  # offered (without it, MCP tools appear but sit behind the headless permission-deny default).
  FINDING=$(cd "$ROOT" 2>/dev/null && printf '%s' "$PROMPT" \
    | TALE_GOVERNOR_ACTIVE=1 $TO claude -p \
        --model "${TALE_GOVERNOR_MODEL:-claude-sonnet-4-6}" \
        --strict-mcp-config \
        --tools Read Grep Glob 2>/dev/null || true)
else
  OUTF=$(mktemp 2>/dev/null) || exit 0
  TALE_GOVERNOR_ACTIVE=1 $TO codex exec --skip-git-repo-check --ephemeral -s read-only \
    -C "$ROOT" -o "$OUTF" "$PROMPT" >/dev/null 2>&1 || true
  FINDING=$(cat "$OUTF" 2>/dev/null || true)
  rm -f "$OUTF" 2>/dev/null || true
fi

# 8. Advisory only. head (not tail): on a non-compliant "finding then elaboration" reply, the
#    FIRST 600 bytes carry the actual finding. Empty / NOTHING -> stay silent; a concrete
#    finding -> systemMessage (renders on both hosts). Never a decision; L1 owns the block.
FINDING=$(printf '%s' "$FINDING" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | head -c 600)
# A byte-count cut can split a multibyte UTF-8 char, which would make jq --arg reject the whole
# string and silently drop the advisory — strip any torn trailing sequence (iconv -c) when we can.
command -v iconv >/dev/null 2>&1 && FINDING=$(printf '%s' "$FINDING" | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null || printf '%s' "$FINDING")
[ -n "$FINDING" ] || exit 0
case "$FINDING" in NOTHING|nothing|Nothing*) exit 0 ;; esac
jq -n --arg f "$FINDING" '{systemMessage: ("tale-mode governor (fresh-eyes, read-only): " + $f)}'
exit 0
