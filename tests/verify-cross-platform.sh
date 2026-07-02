#!/usr/bin/env bash
# tale-mode — cross-platform verification gate (Claude Code + Codex).
#
# Deterministic: exits 0 ONLY when every check passes. Designed to be the autonomous-loop `check`
# (write {"check":"bash tests/verify-cross-platform.sh"} to .claude/active-goal.json).
#
# It covers everything verifiable WITHOUT a live Codex session:
#   1. the hook logic, against BOTH runtimes' payload shapes (the 3 hook suites) + the skills lint
#   2. Claude Code plugin validity
#   3. Codex parse-compatibility (no top-level `description`; only Codex-known hook events)
#   4. Codex hook ENGAGEMENT — a Codex-shaped Stop payload (cwd-root, no CLAUDE_PROJECT_DIR) blocks
# The one thing it CANNOT check is Codex actually firing the hook at runtime — that is an owner
# smoke (start a Codex session, confirm the parse warning is gone + the loop drives to green).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
fail=0
say(){ printf '  %-4s %s\n' "$1" "$2"; }

echo "[1] unit suites (hook logic, both payload shapes; + the skills structural lint)"
for t in test-stop-goal-loop test-mark-phase test-session-start test-skills test-governor; do
  if bash "tests/$t.sh" >"/tmp/tm-$t.out" 2>&1; then say OK "$t"; else say FAIL "$t  (see /tmp/tm-$t.out)"; fail=1; fi
done

echo "[2] Claude Code plugin validity"
if command -v claude >/dev/null 2>&1; then
  if claude plugin validate . >/dev/null 2>&1; then say OK "claude plugin validate"; else say FAIL "claude plugin validate"; fail=1; fi
else say SKIP "claude CLI not on PATH"; fi

echo "[3] Codex parse-compatibility (every plugin's hooks.json)"
# Events Codex's hook parser accepts (strict serde enum — an unknown event fails the WHOLE file).
# Checked for BOTH plugins: the governor's type:command hook actively RUNS on Codex (v2), so a
# malformed governor hooks.json would both spam a parse warning and silently disable the governor.
KNOWN='SessionStart|SessionEnd|Stop|UserPromptSubmit|PreToolUse|PostToolUse|PermissionRequest|SubagentStart|SubagentStop|PreCompact|PostCompact|Notification'
for hj in plugins/*/hooks/hooks.json; do
  if ! jq -e . "$hj" >/dev/null 2>&1; then say FAIL "$hj is not valid JSON"; fail=1; continue; fi
  ok3=1
  jq -e 'has("description")' "$hj" >/dev/null 2>&1 && { say FAIL "$hj has a top-level \"description\" (Codex rejects it)"; fail=1; ok3=0; }
  for e in $(jq -r '.hooks|keys[]' "$hj"); do
    printf '%s\n' "$e" | grep -qE "^($KNOWN)$" || { say FAIL "$hj event '$e' is unknown to Codex"; fail=1; ok3=0; }
  done
  [ "$ok3" = 1 ] && say OK "$hj: no description + all events Codex-known"
done

echo "[4] Codex hook engagement (cwd-root Stop payload -> block)"
TMP=$(mktemp -d); mkdir -p "$TMP/.claude"
printf '{"goal":"gate","check":"false","rounds":0,"max_rounds":5}' > "$TMP/.claude/active-goal.json"
OUT=$(printf '{"session_id":"cx","cwd":"%s","hook_event_name":"Stop"}' "$TMP" \
        | env -u CLAUDE_PROJECT_DIR TALE_ALLOW_CWD_ROOT=1 bash plugins/tale-mode/hooks/stop-goal-loop.sh 2>/dev/null)
if printf '%s' "$OUT" | jq -e '.decision=="block"' >/dev/null 2>&1; then say OK "Codex cwd-root path engages (decision=block)"; else say FAIL "Codex cwd-root path did NOT block"; fail=1; fi
rm -rf "$TMP"

echo
if [ "$fail" = 0 ]; then echo "CROSS-PLATFORM GATE: PASS"; exit 0; else echo "CROSS-PLATFORM GATE: FAIL"; exit 1; fi
