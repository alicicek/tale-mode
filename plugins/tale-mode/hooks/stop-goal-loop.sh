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

# Project root. Claude Code exports CLAUDE_PROJECT_DIR for hooks; we anchor on it because it is the
# TRUSTED project root and is NOT agent-controllable. By default we do NOT fall back to the hook
# input's cwd for a BLOCKING decision: a stray/sibling .claude/active-goal.json under an
# agent-controlled cwd must never trap an unrelated turn.
#
# Cross-runtime (e.g. OpenAI Codex) does NOT export CLAUDE_PROJECT_DIR, so the only project-root
# signal there is the stdin `cwd`. To preserve the no-cwd-trap guarantee, that fallback stays OFF
# unless the USER opts in for this runtime via TALE_ALLOW_CWD_ROOT=1 (set in the host's env config,
# e.g. Codex's [shell_environment_policy.set]). It is a USER grant, not an agent one: the hook's env
# comes from the host, not the agent's transient shell, so the agent still cannot authorize its own
# enforcement. With the var unset, the path below is byte-identical to v1 (CLAUDE_PROJECT_DIR or
# nothing). Enable it only after confirming on that runtime that the Stop-payload `cwd` is the
# stable workspace root (docs/cross-platform-plan.md, Phase D-core smoke). We accept only an
# absolute, existing directory, so a relative/empty/garbage cwd can never resolve to a root.
ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$ROOT" ] && [ "${TALE_ALLOW_CWD_ROOT:-}" = "1" ] && command -v jq >/dev/null 2>&1; then
  ROOT=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || true)
  case "$ROOT" in
    /*) [ -d "$ROOT" ] || ROOT="" ;;
    *)  ROOT="" ;;
  esac
fi
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

# ============================================================================
# Phase C — committed-config phase auto-arm (gated). This ENTIRE block is skipped unless a
# session-scoped phase marker exists, so a normal turn's decision path is byte-identical to v1
# (Invariant 5). When a DELIBERATE build phase is active for THIS session (the
# /tale-mode:kickoff-phase UserPromptSubmit hook wrote .claude/tale-mode.phase.$SID.json)
# AND the repo ships a .claude/tale-mode.json whose content-hash you've TRUSTED AND the working
# tree is dirty, the loop arms ITSELF on that committed config's `gates` — no agent memory, so it
# can't be forgotten. The committed gates are checked FIRST and block independently, so an ad-hoc
# goal-file (below) may ADD a gate but can NEVER suppress a committed one. `needs_user` still pauses.
# ============================================================================
PHASE_FILE=""
[ -n "$SID" ] && PHASE_FILE="$ROOT/.claude/tale-mode.phase.$SID.json"
if [ -n "$PHASE_FILE" ] && [ -f "$PHASE_FILE" ] && command -v jq >/dev/null 2>&1; then
  # sha256 of a file's content -> bare hex (empty if no hashing tool is available).
  _sha256() {
    if   command -v sha256sum >/dev/null 2>&1; then sha256sum    < "$1" 2>/dev/null | awk '{print $1; exit}'
    elif command -v shasum    >/dev/null 2>&1; then shasum -a 256 < "$1" 2>/dev/null | awk '{print $1; exit}'
    elif command -v openssl   >/dev/null 2>&1; then openssl dgst -sha256 < "$1" 2>/dev/null | awk '{print $NF; exit}'
    fi
  }
  # 0 (trusted) iff the file's content-hash is listed in the user-local trust store. The hook only
  # ever READS this store; granting trust is a manual USER action (see the untrusted notice below) —
  # the hook and the agent never write it, else a malicious repo could self-trust. No hashing tool /
  # no store / not listed -> NOT trusted -> the gates do not run (fail-safe).
  _hash_trusted() {
    local f="$1" store h
    store="${TALE_TRUST_STORE:-${HOME:-}/.claude/tale-mode-trust}"
    h=$(_sha256 "$f"); [ -n "$h" ] || return 1
    [ -f "$store" ] || return 1
    grep -qE "^${h}([[:space:]]|\$)" "$store" 2>/dev/null
  }
  # 0 (dirty) iff the repo has uncommitted changes, EXCLUDING the hook's own runtime files (phase
  # markers + the verdict log + the goal-files) via git pathspecs — NOT the consumer's .gitignore,
  # which we can't assume carries our entries. .claude/deferrals.json is committed work and is
  # deliberately NOT excluded. No git / not a repo -> treated as not-dirty (fail-open: don't enforce)
  # so the loop can never trap on an undecidable dirtiness check.
  _repo_dirty() {
    command -v git >/dev/null 2>&1 || return 1
    local out
    out=$(git -C "$1" status --porcelain --untracked-files=normal -- . \
          ':(exclude).claude/tale-mode.phase.*.json' \
          ':(exclude).claude/tale-mode.log' \
          ':(exclude).claude/active-goal*.json' 2>/dev/null) || return 1
    [ -n "$out" ]
  }
  # Append one fail-safe JSONL verdict line for a committed-gate BLOCK round to the same audit log as
  # the goal-file path (so .claude/tale-mode.log covers committed enforcement too). Pure side-effect —
  # MUST NOT affect the decision: the { } group routes jq's stderr AND any redirect-open failure to
  # /dev/null before >>, then || true. The fd-guard collapses slashes and sends any process-fd target
  # to /dev/null so the line can't interleave with the decision on stdout.
  _plog() {
    local log ln
    log="${TALE_VERDICT_LOG:-$ROOT/.claude/tale-mode.log}"
    ln=$(printf '%s' "$log" | tr -s '/'); ln="${ln%/}"
    case "$ln" in /dev/stdout|/dev/stderr|/dev/fd/*|/proc/self/fd/*|/proc/[0-9]*/fd/*) log=/dev/null ;; esac
    { jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" --arg sid "$1" \
        --argjson round "$2" --arg check "$3" --argjson rc "$4" --arg tail "$5" \
        '{ts:$ts,session:$sid,kind:"phase-gate",round:$round,check:$check,verdict:"fail",rc:$rc,tail:$tail}' \
      >> "$log"; } 2>/dev/null || true
  }

  # Marker hygiene: refresh OUR marker's mtime so the reap can't claim a live phase, then reap stale
  # FOREIGN phase markers (a crashed session never clears its own). Crash backstop only (~24h,
  # distinct from the per-round goal TTL) — never ours, never within the window. Digit-sanitize the
  # TTL override so a non-numeric value can't break the find -mmin expression.
  _TTL="${TALE_PHASE_TTL_MIN:-1440}"; case "$_TTL" in (*[!0-9]*|'') _TTL=1440 ;; esac
  touch "$PHASE_FILE" 2>/dev/null || true
  command -v find >/dev/null 2>&1 && find "$ROOT/.claude" -maxdepth 1 -type f \
    -name 'tale-mode.phase.*.json' ! -name "tale-mode.phase.$SID.json" \
    -mmin +"$_TTL" -delete 2>/dev/null

  CFG="$ROOT/.claude/tale-mode.json"
  if [ -f "$CFG" ]; then
    if _hash_trusted "$CFG"; then
      if _repo_dirty "$ROOT"; then
        # --- committed-config enforcement is LIVE for this turn ---
        # needs_user pause (D1 / Invariant 2): allow THIS stop so the agent can ask the human, but
        # KEEP the marker + gates (re-checked next turn). The agent clears needs_user to resume.
        PNU=$(jq -r '.needs_user // ""' "$PHASE_FILE" 2>/dev/null || true)
        if [ -n "$PNU" ] && [ "$PNU" != "null" ]; then exit 0; fi

        # Hard ceiling -> give up cleanly: disarm the phase (delete marker) and tell the user.
        PR=$(jq -r '.rounds // 0'        "$PHASE_FILE" 2>/dev/null || echo 0)
        PMAX=$(jq -r '.max_rounds // 50' "$PHASE_FILE" 2>/dev/null || echo 50)
        case "$PR"   in (*[!0-9]*|'') PR=0 ;; esac
        case "$PMAX" in (*[!0-9]*|'') PMAX=50 ;; esac
        PR=$((10#$PR)); PMAX=$((10#$PMAX))
        if [ "$PR" -ge "$PMAX" ]; then
          rm -f "$PHASE_FILE" 2>/dev/null || true
          jq -n --arg n "$PMAX" '{systemMessage: ("tale-mode phase loop: hit max_rounds (" + $n + ") with committed gates still red. Stopped enforcing — fix and re-run /tale-mode:kickoff-phase, or take over.")}'
          exit 0
        fi

        # Run the committed gates IN ORDER; block on the FIRST red one. Same exec model as the
        # goal-file `check`: arbitrary (trusted) shell from the project root, optional timeout. Each
        # gate is ONE shell command (a multi-line JSON value would split on newlines). The gate runs
        # with stdin from /dev/null so a gate that reads stdin (a test runner, `cat`, `read`) cannot
        # drain the gate-list pipe and silently skip the gates after it.
        TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout ${TALE_CHECK_TIMEOUT:-120}"
        GATE_FAIL=""; GATE_RC=0; GATE_OUT=""
        while IFS= read -r _gate; do
          [ -n "$_gate" ] || continue
          _out=$( cd "$ROOT" 2>/dev/null && $TO bash -c "$_gate" </dev/null 2>&1 ); _rc=$?
          if [ "$_rc" -ne 0 ]; then GATE_FAIL="$_gate"; GATE_RC=$_rc; GATE_OUT="$_out"; break; fi
        done < <(jq -r '.gates[]?' "$CFG" 2>/dev/null)

        if [ -n "$GATE_FAIL" ]; then
          GTAIL=$(printf '%s' "$GATE_OUT" | tail -c 1200)
          # Advance the phase round counter (fail-open: if we cannot PERSIST it, allow the stop — a
          # frozen counter would never reach max_rounds and would trap the session forever).
          PNEXT=$((PR + 1))
          PTMP=$(mktemp 2>/dev/null || echo "$PHASE_FILE.tmp")
          if jq --argjson r "$PNEXT" '.rounds=$r' "$PHASE_FILE" > "$PTMP" 2>/dev/null && mv "$PTMP" "$PHASE_FILE" 2>/dev/null; then :; else
            rm -f "$PTMP" 2>/dev/null
            jq -n '{systemMessage:"tale-mode: cannot persist phase rounds (read-only/locked dir) — stopping to avoid an unbounded loop."}'
            exit 0
          fi
          _plog "$SID" "$PNEXT" "$GATE_FAIL" "$GATE_RC" "$GTAIL"   # durable cross-session audit (fail-safe)
          PREASON=$(printf 'Committed gate NOT met (phase round %s/%s).

Gate `%s` exited %s. Last output:
%s

Keep going. This gate is committed in .claude/tale-mode.json and review-gated — do NOT weaken it; drive the work to green. Foundation-first: confirm the artifact EXISTS and the environment is CAPABLE before fixing symptoms. Two-strike: if two fixes in a row failed, STOP and re-verify the foundational assumption instead of trying a third. If you genuinely need the user (a secret, a login, a go/no-go), set "needs_user" in .claude/tale-mode.phase.%s.json to pause and ask — that pauses without clearing the gate.' \
            "$PNEXT" "$PMAX" "$GATE_FAIL" "$GATE_RC" "$GTAIL" "$SID")
          jq -n --arg r "$PREASON" '{decision:"block", reason:$r}'
          exit 0
        fi
        # All committed gates GREEN -> fall through to the ad-hoc goal-file logic below (AND-combine:
        # committed gates passing does not by itself end the turn if a goal-file check still fails).
      fi
    else
      # tale-mode.json is present but its content-hash is NOT trusted -> its gates do NOT run (C8).
      # Surface a one-time review-and-trust notice (deduped via the marker), but ONLY when there is
      # no ad-hoc goal-file that could block this turn — so stdout stays exactly one JSON object.
      if _repo_dirty "$ROOT" && [ ! -f "$GOAL_FILE" ]; then
        _TN=$(jq -r '.trust_notified // false' "$PHASE_FILE" 2>/dev/null || echo false)
        if [ "$_TN" != "true" ]; then
          _H=$(_sha256 "$CFG"); _STORE="${TALE_TRUST_STORE:-${HOME:-}/.claude/tale-mode-trust}"
          { jq '.trust_notified=true' "$PHASE_FILE" > "$PHASE_FILE.tn" 2>/dev/null && mv "$PHASE_FILE.tn" "$PHASE_FILE" 2>/dev/null; } || rm -f "$PHASE_FILE.tn" 2>/dev/null
          jq -n --arg h "${_H:-<run: shasum -a 256 .claude/tale-mode.json>}" --arg s "$_STORE" \
            '{systemMessage: ("tale-mode: a committed .claude/tale-mode.json is present but its content-hash is NOT trusted, so the phase gates will NOT run. Review the gates, then trust this exact content by adding its hash to " + $s + ":\n    " + $h + "  # tale-mode gates\nThe ad-hoc goal-file loop (if any) is unaffected.")}'
          exit 0
        fi
      fi
    fi
  fi
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
  jq -n --arg g "$GOAL" --arg n "$MAX" \
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
