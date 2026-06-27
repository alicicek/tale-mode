#!/usr/bin/env bash
# Proves stop-goal-loop.sh's fail/pass/edge cases by feeding it the exact Stop-hook
# input + goal-files and asserting the output, exit code, and file state. This is the
# "test the mechanic, not assert it" gate for the deterministic core. (The runtime
# behaviour — that Claude Code actually re-runs the turn on a block — can only be
# verified in a live session; see the SKILL.md live-test.)
set -uo pipefail
HOOK="$(cd "$(dirname "$0")/../plugins/tale-mode/hooks" && pwd)/stop-goal-loop.sh"
PASS=0; FAIL=0; WORK=""
SID="s1testsession"   # a fixed, valid session id -> the scoped goal-file path the hook now uses

newwork() { WORK=$(mktemp -d); mkdir -p "$WORK/.claude"; }
gf()      { echo "$WORK/.claude/active-goal.$SID.json"; }   # where the goal lives after the hook adopts it
vlog()    { echo "$WORK/.claude/tale-mode.log"; }          # Phase B: where the per-round verdict log lands
arm()     { printf '%s' "$1" > "$WORK/.claude/active-goal.json"; }   # the agent writes the SIMPLE path; the hook claims it
run()     { OUT=$(printf '{"session_id":"%s","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$SID" "$WORK" \
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
newwork; printf '%s' '{"goal":"g","check":"false","rounds":3,"max_rounds":25}' > "$(gf)"; chmod 555 "$WORK/.claude"; run; chmod 755 "$WORK/.claude"
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

echo "13) session-scoped: a goal armed by session A does NOT trap session B"
newwork
printf '%s' '{"goal":"A","check":"false","rounds":0,"max_rounds":25}' > "$WORK/.claude/active-goal.sessA.json"
OUT=$(printf '{"session_id":"sessB","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$WORK" | CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK"); RC=$?
ok "exit 0"                    '[ "$RC" -eq 0 ]'
ok "B not blocked by A's goal" '! printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null 2>&1'
ok "A's goal untouched"        '[ -f "$WORK/.claude/active-goal.sessA.json" ]'

echo "14) no session_id -> legacy unsuffixed goal-file still works (v1 fallback)"
newwork
printf '%s' '{"goal":"legacy","check":"false","rounds":0,"max_rounds":25}' > "$WORK/.claude/active-goal.json"
OUT=$(printf '{"cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$WORK" | CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK"); RC=$?
ok "legacy path blocks"        'printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null'

echo "15) reap: a STALE foreign goal-file is removed; the live one is kept"
newwork
printf '%s' '{"goal":"current","check":"false","rounds":0,"max_rounds":25}' > "$WORK/.claude/active-goal.live.json"
printf '%s' '{"goal":"orphan","check":"false","rounds":0,"max_rounds":25}' > "$WORK/.claude/active-goal.dead.json"
touch -t 202001010000 "$WORK/.claude/active-goal.dead.json"
OUT=$(printf '{"session_id":"live","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$WORK" | CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK"); RC=$?
ok "stale foreign reaped"      '[ ! -f "$WORK/.claude/active-goal.dead.json" ]'
ok "current goal kept"         '[ -f "$WORK/.claude/active-goal.live.json" ]'

echo "16) Phase B: a FAILING round appends a JSONL verdict line (fail/round/rc/check)"
newwork; arm '{"goal":"audit me","check":"echo boom; false","rounds":0,"max_rounds":25}'; run
ok "decision=block"            'printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null'
ok "log written"               '[ -f "$(vlog)" ]'
ok "last line is valid JSON"   'tail -n1 "$(vlog)" | jq -e . >/dev/null'
ok "verdict=fail"              '[ "$(tail -n1 "$(vlog)" | jq -r .verdict)" = "fail" ]'
ok "round=1 (ROUNDS+1)"        '[ "$(tail -n1 "$(vlog)" | jq -r .round)" = "1" ]'
ok "rc nonzero"                '[ "$(tail -n1 "$(vlog)" | jq -r .rc)" != "0" ]'
ok "check recorded verbatim"   '[ "$(tail -n1 "$(vlog)" | jq -r .check)" = "echo boom; false" ]'

echo "17) Phase B: a PASSING round appends a JSONL verdict line (pass) + the goal still clears"
newwork; arm '{"goal":"audit me","check":"true","rounds":2,"max_rounds":25}'; run
ok "NOT blocking"              '! printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null 2>&1'
ok "goal-file cleared"         '[ ! -f "$(gf)" ]'
ok "log written"               '[ -f "$(vlog)" ]'
ok "verdict=pass"              '[ "$(tail -n1 "$(vlog)" | jq -r .verdict)" = "pass" ]'
ok "round=3 (ROUNDS+1)"        '[ "$(tail -n1 "$(vlog)" | jq -r .round)" = "3" ]'

echo "18) Phase B: verdict-log write FAILS (unwritable path) -> decision UNCHANGED, rounds++, stderr silent (leak guard)"
newwork; arm '{"goal":"g","check":"false","rounds":0,"max_rounds":25}'
OUT=$(printf '{"session_id":"%s","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$SID" "$WORK" \
      | TALE_VERDICT_LOG="$WORK/nope/tale.log" CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK" 2>"$WORK/err.txt"); RC=$?
ERR=$(cat "$WORK/err.txt")
ok "exit 0"                    '[ "$RC" -eq 0 ]'
ok "still blocks (decision unchanged)" 'printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null'
ok "rounds still incremented"  '[ "$(jq -r .rounds "$(gf)")" = "1" ]'
ok "stderr silent (the leak guard)"    '[ -z "$ERR" ]'
ok "default log NOT written"   '[ ! -f "$(vlog)" ]'

echo "19) Phase B: TALE_VERDICT_LOG stdout-aliases must NOT pollute the decision stdout (purity guard)"
newwork; arm '{"goal":"g","check":"false","rounds":0,"max_rounds":25}'
OUT=$(printf '{"session_id":"%s","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$SID" "$WORK" \
      | TALE_VERDICT_LOG=/dev/stdout CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK"); RC=$?
ok "exit 0"                    '[ "$RC" -eq 0 ]'
ok "stdout is exactly ONE JSON object" '[ "$(printf "%s" "$OUT" | jq -s "length")" = "1" ]'
ok "that one object is the decision"   'printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null'
# a slash-variant alias (//dev/stdout) must ALSO be guarded — exact-string match alone would leak it
newwork; arm '{"goal":"g","check":"false","rounds":0,"max_rounds":25}'
OUT=$(printf '{"session_id":"%s","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$SID" "$WORK" \
      | TALE_VERDICT_LOG=//dev/stdout CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK"); RC=$?
ok "slash-variant //dev/stdout also guarded" '[ "$(printf "%s" "$OUT" | jq -s "length")" = "1" ]'
# a leading-zero fd alias (/dev/fd/01) — macOS resolves it to fd1, so the guard must catch it too
newwork; arm '{"goal":"g","check":"false","rounds":0,"max_rounds":25}'
OUT=$(printf '{"session_id":"%s","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$SID" "$WORK" \
      | TALE_VERDICT_LOG=/dev/fd/01 CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK"); RC=$?
ok "exit 0"                              '[ "$RC" -eq 0 ]'
ok "fd-alias /dev/fd/01 also guarded"    '[ "$(printf "%s" "$OUT" | jq -s "length")" = "1" ]'

echo '20) hardening: a leading-zero STRING rounds ("08") must NOT crash $((...)) — read as base-10'
newwork; arm '{"goal":"g","check":"false","rounds":"08","max_rounds":25}'
OUT=$(printf '{"session_id":"%s","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$SID" "$WORK" \
      | CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK" 2>"$WORK/err.txt"); RC=$?
ERR=$(cat "$WORK/err.txt")
ok "exit 0 (no crash)"         '[ "$RC" -eq 0 ]'
ok "decision=block (emitted)"  'printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null'
ok "stderr silent (no octal error)"   '[ -z "$ERR" ]'
ok "rounds advanced 8 -> 9 (base-10, not octal/string)" '[ "$(jq -r .rounds "$(gf)")" = "9" ]'

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
