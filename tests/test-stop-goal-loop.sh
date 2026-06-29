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

# --- Phase C: committed-config helpers. Each case gets its own GIT repo; the trust store and the
#     stderr capture live OUTSIDE the repo so they never show up as "dirty" and skew enforcement. ---
CSID="cphase1session"   # a fixed, valid session token for the committed-config cases
_h256()   { if   command -v sha256sum >/dev/null 2>&1; then sha256sum    < "$1" | awk '{print $1}';
            elif command -v shasum    >/dev/null 2>&1; then shasum -a 256 < "$1" | awk '{print $1}';
            else                                              openssl dgst -sha256 < "$1" | awk '{print $NF}'; fi; }
cwork()   { WORK=$(mktemp -d); git -C "$WORK" init -q; git -C "$WORK" config user.email t@t; git -C "$WORK" config user.name t; mkdir -p "$WORK/.claude"; CTRUST=$(mktemp); CERR=$(mktemp); }
pf()      { echo "$WORK/.claude/tale-mode.phase.$CSID.json"; }   # the phase marker / committed-loop state file
cmark()   { printf '{"session":"%s","rounds":%s,"max_rounds":%s,"needs_user":%s}\n' "$CSID" "${1:-0}" "${2:-50}" "${3:-null}" > "$(pf)"; }
ccfg()    { printf '%s' "$1" > "$WORK/.claude/tale-mode.json"; }
ctrust()  { printf '%s  # test gates\n' "$(_h256 "$WORK/.claude/tale-mode.json")" > "$CTRUST"; }   # trust THIS config's hash
cuntrust(){ : > "$CTRUST"; }                                                                        # empty store -> untrusted
cbase()   { git -C "$WORK" add -A; git -C "$WORK" commit -qm base; }   # clean, committed baseline
cdirty()  { echo "real work" > "$WORK/src.txt"; }                       # a NON-excluded uncommitted change
crun()    { OUT=$(printf '{"session_id":"%s","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$CSID" "$WORK" \
              | CLAUDE_PROJECT_DIR="$WORK" TALE_TRUST_STORE="$CTRUST" bash "$HOOK" 2>"$CERR"); RC=$?; CERRTXT=$(cat "$CERR"); }
cpr()     { jq -r '.rounds' "$(pf)" 2>/dev/null; }

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

echo "21) Phase C: committed config trusted + dirty + FAILING gate -> auto-arm: block + phase rounds++"
cwork; cmark 0; ccfg '{"gates":["false"],"doneWhen":"gatesGreen"}'; ctrust; cdirty; crun
ok "exit 0"                       '[ "$RC" -eq 0 ]'
ok "decision=block"               'printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null'
ok "reason names the committed gate" 'printf "%s" "$OUT" | jq -r ".reason" | grep -q "Committed gate"'
ok "phase rounds -> 1"            '[ "$(cpr)" = "1" ]'
ok "stderr silent"               '[ -z "$CERRTXT" ]'

echo "22) committed config trusted + dirty + PASSING gate, no goal -> allow (silent), rounds unchanged"
cwork; cmark 0; ccfg '{"gates":["true"]}'; ctrust; cdirty; crun
ok "exit 0"                       '[ "$RC" -eq 0 ]'
ok "no decision (allow)"          '! printf "%s" "$OUT" | jq -e ".decision" >/dev/null 2>&1'
ok "phase rounds still 0"         '[ "$(cpr)" = "0" ]'

echo "23) C8 trust gate governs EXECUTION: an untrusted gate must NOT run; a trusted one runs (side-effect proof)"
cwork; cmark 0; ccfg "{\"gates\":[\"touch $WORK/RAN\"]}"; cdirty
cuntrust; crun
ok "untrusted: systemMessage NOT trusted" 'printf "%s" "$OUT" | jq -r ".systemMessage" | grep -q "NOT trusted"'
ok "untrusted: gate did NOT execute"      '[ ! -e "$WORK/RAN" ]'
ctrust; crun
ok "trusted: gate DID execute (side effect appears)" '[ -e "$WORK/RAN" ]'
ok "trusted: gate passed -> no block"     '! printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null 2>&1'

echo "24) committed config trusted but CLEAN tree -> no enforce (only real work is taxed)"
cwork; cmark 0; ccfg '{"gates":["false"]}'; ctrust; cbase; crun
ok "exit 0"                       '[ "$RC" -eq 0 ]'
ok "no decision (clean = no enforce)" '! printf "%s" "$OUT" | jq -e ".decision" >/dev/null 2>&1'

echo "25) C7: ONLY the hook's own files changed (log + marker) -> NOT dirty -> no enforce"
cwork; cmark 0; ccfg '{"gates":["false"]}'; ctrust; cbase
printf '{}' > "$WORK/.claude/tale-mode.log"; cmark 5   # rewrite ONLY excluded files
crun
ok "no enforce (own files excluded)" '! printf "%s" "$OUT" | jq -e ".decision" >/dev/null 2>&1'

echo "26) C7 control: a non-excluded change present -> IS dirty -> the guard fires (proves it is not inert)"
cwork; cmark 0; ccfg '{"gates":["false"]}'; ctrust; cbase; cdirty; crun
ok "blocks when real work present" 'printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null'

echo "27) Inv6: .claude/deferrals.json is NOT excluded -> editing it counts as dirty -> enforce"
cwork; cmark 0; ccfg '{"gates":["false"]}'; ctrust; cbase
printf '{"deferrals":[]}' > "$WORK/.claude/deferrals.json"   # untracked, deliberately NOT excluded
crun
ok "deferrals.json counts as dirty" 'printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null'

echo "28) C5 precedence: committed FAILS + ad-hoc goal that PASSES -> committed blocks first (no suppression)"
cwork; cmark 0; ccfg '{"gates":["false"]}'; ctrust; cdirty
printf '{"goal":"g","check":"true","rounds":0,"max_rounds":25}' > "$WORK/.claude/active-goal.$CSID.json"
crun
ok "blocks on the committed gate" 'printf "%s" "$OUT" | jq -r ".reason" | grep -q "Committed gate"'

echo "29) AND-combine: committed PASSES + ad-hoc goal FAILS -> blocks on the goal"
cwork; cmark 0; ccfg '{"gates":["true"]}'; ctrust; cdirty
printf '{"goal":"g","check":"false","rounds":0,"max_rounds":25}' > "$WORK/.claude/active-goal.$CSID.json"
crun
ok "blocks on the goal-file check" 'printf "%s" "$OUT" | jq -r ".reason" | grep -q "Goal NOT met"'

echo "30) needs_user in the marker -> PAUSE (allow, keep marker, gates not run) [D1 / Invariant 2]"
cwork; cmark 0 50 '"need a secret only you have"'; ccfg '{"gates":["false"]}'; ctrust; cdirty; crun
ok "exit 0 (paused)"             '[ "$RC" -eq 0 ]'
ok "no block"                    '! printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null 2>&1'
ok "marker kept"                 '[ -f "$(pf)" ]'
ok "rounds NOT advanced (gate not run)" '[ "$(cpr)" = "0" ]'

echo "31) committed max_rounds -> give up cleanly: delete marker + systemMessage"
cwork; cmark 50 50; ccfg '{"gates":["false"]}'; ctrust; cdirty; crun
ok "exit 0"                      '[ "$RC" -eq 0 ]'
ok "systemMessage hit max_rounds" 'printf "%s" "$OUT" | jq -r ".systemMessage" | grep -q "max_rounds"'
ok "marker deleted (disarmed)"   '[ ! -f "$(pf)" ]'

echo "32) fail-open: cannot persist phase rounds (read-only .claude) -> allow, never trap"
cwork; cmark 0; ccfg '{"gates":["false"]}'; ctrust; cdirty
chmod 555 "$WORK/.claude"; crun; chmod 755 "$WORK/.claude"
ok "exit 0"                      '[ "$RC" -eq 0 ]'
ok "no block (failed open)"      '! printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null 2>&1'
ok "systemMessage cannot persist" 'printf "%s" "$OUT" | jq -r ".systemMessage" | grep -q "cannot persist phase rounds"'

echo "33) Inv5: a phase marker but NO tale-mode.json -> committed block inert; ad-hoc goal-file logic only"
cwork; cmark 0; cdirty
printf '{"goal":"g","check":"false","rounds":0,"max_rounds":25}' > "$WORK/.claude/active-goal.$CSID.json"
crun
ok "falls through to the goal-file (blocks on goal)" 'printf "%s" "$OUT" | jq -r ".reason" | grep -q "Goal NOT met"'

echo "34) stdin-eating gate must NOT skip later gates (</dev/null): gates [cat, false] -> still blocks on 'false'"
cwork; cmark 0; ccfg '{"gates":["cat","false"]}'; ctrust; cdirty; crun
ok "blocks (gate 2 ran despite cat)" 'printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null'
ok "reason names the failing gate 'false'" 'printf "%s" "$OUT" | jq -r ".reason" | grep -q "Gate .false. exited"'

echo "35) committed-gate block writes a verdict line to the audit log (kind=phase-gate)"
cwork; cmark 0; ccfg '{"gates":["false"]}'; ctrust; cdirty; crun
ok "log written"               '[ -f "$(vlog)" ]'
ok "last line valid JSON"      'tail -n1 "$(vlog)" | jq -e . >/dev/null'
ok "kind=phase-gate"           '[ "$(tail -n1 "$(vlog)" | jq -r .kind)" = "phase-gate" ]'
ok "verdict=fail + round=1"    '[ "$(tail -n1 "$(vlog)" | jq -r .verdict)" = "fail" ] && [ "$(tail -n1 "$(vlog)" | jq -r .round)" = "1" ]'

echo "36) untrusted config + CLEAN tree -> silent (the notice only fires when there is real work)"
cwork; cmark 0; ccfg '{"gates":["false"]}'; cuntrust; cbase; crun
ok "exit 0"                    '[ "$RC" -eq 0 ]'
ok "silent (no notice on a clean tree)" '[ -z "$OUT" ]'

echo "37) foreign phase-marker reap: a stale OTHER-session marker is removed; ours is kept"
cwork; cmark 0
printf '%s' '{"session":"dead","rounds":0}' > "$WORK/.claude/tale-mode.phase.deadsession.json"
touch -t 202001010000 "$WORK/.claude/tale-mode.phase.deadsession.json"
crun
ok "stale foreign marker reaped" '[ ! -f "$WORK/.claude/tale-mode.phase.deadsession.json" ]'
ok "our live marker kept"        '[ -f "$(pf)" ]'

echo "38) untrusted notice dedups (fires once) and leaves the marker valid JSON"
cwork; cmark 0; ccfg '{"gates":["false"]}'; cuntrust; cdirty; crun
ok "run 1 emits the trust notice" 'printf "%s" "$OUT" | jq -r ".systemMessage" | grep -q "NOT trusted"'
crun
ok "run 2 is silent (deduped)"    '[ -z "$OUT" ]'
ok "marker still valid JSON"      'jq -e . "$(pf)" >/dev/null'

echo "39) Codex shape: CLAUDE_PROJECT_DIR unset + opt-in OFF -> still no-op (default-safe == v1)"
newwork; arm '{"goal":"g","check":"false","rounds":0,"max_rounds":25}'
OUT=$(printf '{"session_id":"%s","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$SID" "$WORK" | env -u CLAUDE_PROJECT_DIR bash "$HOOK"); RC=$?
ok "exit 0"                       '[ "$RC" -eq 0 ]'
ok "NOT blocking (no cwd-root without opt-in)" '! printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null 2>&1'

echo "40) Codex shape: CLAUDE_PROJECT_DIR unset + TALE_ALLOW_CWD_ROOT=1 -> cwd becomes root, loop ENGAGES"
newwork; arm '{"goal":"g","check":"false","rounds":0,"max_rounds":25}'
OUT=$(printf '{"session_id":"%s","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$SID" "$WORK" | env -u CLAUDE_PROJECT_DIR TALE_ALLOW_CWD_ROOT=1 bash "$HOOK"); RC=$?
ok "exit 0"                       '[ "$RC" -eq 0 ]'
ok "decision=block"               'printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null'
ok "rounds incremented to 1"      '[ "$(jq -r .rounds "$(gf)")" = "1" ]'

echo "41) opt-in ON but cwd is relative/nonexistent -> rejected, no-op (only an absolute existing dir is a root)"
newwork; arm '{"goal":"g","check":"false","rounds":0,"max_rounds":25}'
OUT=$(printf '{"session_id":"%s","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$SID" "relative/not/abs" | env -u CLAUDE_PROJECT_DIR TALE_ALLOW_CWD_ROOT=1 bash "$HOOK"); RC=$?
ok "exit 0"                       '[ "$RC" -eq 0 ]'
ok "NOT blocking (bad cwd rejected)" '! printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null 2>&1'

echo "42) CC precedence: CLAUDE_PROJECT_DIR set WINS even with opt-in on (payload cwd ignored)"
newwork; arm '{"goal":"g","check":"false","rounds":0,"max_rounds":25}'; BOGUS=$(mktemp -d); mkdir -p "$BOGUS/.claude"
# Plant a TRAP goal under the payload cwd. If the cwd were (wrongly) adopted as root, the hook would
# claim THIS file (mv it to the scoped path) and its check:"true" would pass -> clear -> NO block.
# So a block from WORK + this trap surviving untouched (still at the legacy path, rounds==0) together
# prove CLAUDE_PROJECT_DIR won, not the cwd. (The old '! -d $BOGUS/.claude' check passed vacuously.)
printf '%s' '{"goal":"trap","check":"true","rounds":0,"max_rounds":25}' > "$BOGUS/.claude/active-goal.json"
OUT=$(printf '{"session_id":"%s","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$SID" "$BOGUS" | CLAUDE_PROJECT_DIR="$WORK" TALE_ALLOW_CWD_ROOT=1 bash "$HOOK"); RC=$?
ok "decision=block"               'printf "%s" "$OUT" | jq -e ".decision==\"block\"" >/dev/null'
ok "armed against CLAUDE_PROJECT_DIR (rounds in WORK)" '[ "$(jq -r .rounds "$(gf)")" = "1" ]'
ok "payload-cwd trap left untouched (cwd ignored)" '[ "$(jq -r .rounds "$BOGUS/.claude/active-goal.json")" = "0" ]'
rm -rf "$BOGUS"

echo "43) Codex shape + opt-in ON but jq ABSENT -> fail-open no-op (the jq guard on the cwd-root branch must hold)"
# The cwd-root branch is gated on 'command -v jq'; without it the branch must be SKIPPED, leaving
# ROOT empty so the hook exits 0 silently. Run with a PATH that has NO jq (symlink only bash+cat into
# a temp bin) to lock that invariant: if a refactor ever parsed cwd without jq while dropping this
# guard, the armed goal below would be adopted under the cwd and trap the turn -> these asserts fire.
newwork; arm '{"goal":"g","check":"false","rounds":0,"max_rounds":25}'
NOJQ=$(mktemp -d); for _b in bash cat; do ln -s "$(command -v "$_b")" "$NOJQ/$_b"; done
OUT=$(printf '{"session_id":"%s","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$SID" "$WORK" \
        | env -u CLAUDE_PROJECT_DIR TALE_ALLOW_CWD_ROOT=1 PATH="$NOJQ" bash "$HOOK"); RC=$?
ok "exit 0"                            '[ "$RC" -eq 0 ]'
ok "silent no-op (no cwd-root, no block)" '[ -z "$OUT" ]'
ok "armed goal NOT claimed under cwd"     '[ ! -f "$(gf)" ]'
rm -rf "$NOJQ"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
