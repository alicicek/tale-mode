#!/usr/bin/env bash
# Proves stop-goal-loop.sh's fail/pass/edge cases by feeding it the exact Stop-hook
# input + goal-files and asserting the output, exit code, and file state. This is the
# "test the mechanic, not assert it" gate for the deterministic core. (The runtime
# behaviour — that Claude Code actually re-runs the turn on a block — can only be
# verified in a live session; see the SKILL.md live-test.)
set -uo pipefail
HOOK="$(cd "$(dirname "$0")" && pwd)/stop-goal-loop.sh"
PASS=0; FAIL=0; WORK=""

newwork() { WORK=$(mktemp -d); mkdir -p "$WORK/.claude"; }
gf()      { echo "$WORK/.claude/active-goal.json"; }
arm()     { printf '%s' "$1" > "$(gf)"; }
run()     { OUT=$(printf '{"cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$WORK" \
              | CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK"); RC=$?; }   # pin ROOT to WORK (safe + deterministic)
ok()      { if eval "$2"; then echo "  PASS  $1"; PASS=$((PASS+1)); else echo "  FAIL  $1  | OUT=<$OUT> RC=$RC"; FAIL=$((FAIL+1)); fi; }

echo "1) no goal-file -> silent no-op"
newwork; run
ok "exit 0"            '[ "$RC" -eq 0 ]'
ok "no output"         '[ -z "$OUT" ]'

echo "2) check FAILS -> block + rounds++"
newwork; arm '{"goal":"demo goal","check":"false","rounds":0,"max_rounds":25}'; run
ok "exit 0"            '[ "$RC" -eq 0 ]'
ok "decision=block"    'printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null'
ok "reason steers"     'printf "%s" "$OUT" | jq -r ".reason" | grep -q "Foundation-first"'
ok "file kept"         '[ -f "$(gf)" ]'
ok "rounds incremented to 1" '[ "$(jq -r .rounds "$(gf)")" = "1" ]'

echo "3) check PASSES -> allow + clear"
newwork; arm '{"goal":"demo goal","check":"true","rounds":2,"max_rounds":25}'; run
ok "exit 0"            '[ "$RC" -eq 0 ]'
ok "NOT blocking"      '! printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null 2>&1'
ok "file cleared"      '[ ! -f "$(gf)" ]'

echo "4) max_rounds -> give up, clear, allow + tell user"
newwork; arm '{"goal":"demo goal","check":"false","rounds":25,"max_rounds":25}'; run
ok "exit 0"            '[ "$RC" -eq 0 ]'
ok "NOT blocking"      '! printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null 2>&1'
ok "file cleared"      '[ ! -f "$(gf)" ]'
ok "systemMessage"     'printf "%s" "$OUT" | jq -e ".systemMessage" >/dev/null'

echo "5) malformed (no check) -> clear, allow, no trap"
newwork; arm '{"goal":"x","rounds":0}'; run
ok "exit 0"            '[ "$RC" -eq 0 ]'
ok "file cleared"      '[ ! -f "$(gf)" ]'

echo "6) check with a pipe (real shape) fails -> block"
newwork; arm '{"goal":"e2e","check":"echo nope | grep -q PASSED","rounds":0,"max_rounds":25}'; run
ok "decision=block"    'printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null'

echo "7) check with a pipe passes -> allow + clear"
newwork; arm '{"goal":"e2e","check":"echo PASSED | grep -q PASSED","rounds":0,"max_rounds":25}'; run
ok "NOT blocking"      '! printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null 2>&1'
ok "file cleared"      '[ ! -f "$(gf)" ]'

echo "8) needs_user set -> pause: allow stop, KEEP file (so the loop resumes after asking)"
newwork; arm '{"goal":"g","check":"false","rounds":1,"max_rounds":25,"needs_user":"need a token only you can create"}'; run
ok "exit 0"            '[ "$RC" -eq 0 ]'
ok "NOT blocking"      '! printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null 2>&1'
ok "file kept"         '[ -f "$(gf)" ]'

echo "9) needs_user back to null -> loop resumes (check fails -> block)"
newwork; arm '{"goal":"g","check":"false","rounds":1,"max_rounds":25,"needs_user":null}'; run
ok "decision=block"    'printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null'

echo "10) rounds-rewrite FAILS (read-only .claude) -> fail OPEN, never block forever"
newwork; arm '{"goal":"g","check":"false","rounds":3,"max_rounds":25}'; chmod 555 "$WORK/.claude"; run; chmod 755 "$WORK/.claude"
ok "exit 0"            '[ "$RC" -eq 0 ]'
ok "NOT blocking"      '! printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null 2>&1'
ok "fail-open message" 'printf "%s" "$OUT" | jq -r ".systemMessage" | grep -q "cannot persist"'

echo "11) whitespace-only check -> disarm, NOT a false 'goal met'"
newwork; arm '{"goal":"g","check":"   ","rounds":0,"max_rounds":25}'; run
ok "NOT blocking"      '! printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null 2>&1'
ok "file cleared"      '[ ! -f "$(gf)" ]'
ok "no-usable-check msg" 'printf "%s" "$OUT" | jq -r ".systemMessage" | grep -q "no usable check"'

echo "12) CLAUDE_PROJECT_DIR unset -> no-op (never arms against a cwd-controlled path)"
newwork; arm '{"goal":"g","check":"false","rounds":0,"max_rounds":25}'
OUT=$(printf '{"cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$WORK" | env -u CLAUDE_PROJECT_DIR bash "$HOOK"); RC=$?
ok "exit 0"            '[ "$RC" -eq 0 ]'
ok "NOT blocking"      '! printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null 2>&1'

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
