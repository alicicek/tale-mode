#!/usr/bin/env bash
# tale-mode — tests for the plan-mode read-only auto-approve hook (PreToolUse, matcher Bash).
#
# The hook's contract is ONE-DIRECTIONAL: its only possible output is an "allow" decision for a
# command every segment of which is provably read-only, in plan mode only. Everything else —
# writes, smuggling (substitution/heredoc/redirects/background), unknown binaries, sensitive
# paths, other permission modes, other tools, unparseable input — must produce NO output and
# exit 0 (no decision -> the normal permission dialog). The FAIL cases are the point: a guard
# that can't fail isn't a guard.
set -uo pipefail
HOOK="$(cd "$(dirname "$0")/../plugins/tale-mode/hooks" && pwd)/approve-readonly.sh"
PASS=0; FAIL=0

payload() { jq -cn --arg m "$1" --arg c "$2" \
  '{session_id:"t1",permission_mode:$m,tool_name:"Bash",tool_input:{command:$c},cwd:"/tmp"}'; }

allow() { # allow <cmd> [label]
  local c="$1" lbl="${2:-$1}"
  OUT=$(payload plan "$c" | bash "$HOOK" 2>/dev/null); RC=$?
  if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision=="allow"' >/dev/null 2>&1; then
    PASS=$((PASS+1)); printf 'ok   - allow : %s\n' "$lbl"
  else
    FAIL=$((FAIL+1)); printf 'FAIL - allow : %s (rc=%s out=%s)\n' "$lbl" "$RC" "$OUT"
  fi
}

prompt() { # prompt <cmd> [label] [mode] -> hook must stay SILENT (no decision)
  local c="$1" lbl="${2:-$1}" mode="${3-plan}"   # ${3-}: an explicit EMPTY mode must stay empty
  OUT=$(payload "$mode" "$c" | bash "$HOOK" 2>/dev/null); RC=$?
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
    PASS=$((PASS+1)); printf 'ok   - prompt: %s\n' "$lbl"
  else
    FAIL=$((FAIL+1)); printf 'FAIL - prompt: %s (rc=%s out=%s)\n' "$lbl" "$RC" "$OUT"
  fi
}

echo "1) plan mode + provably read-only -> allow (the feature)"
allow 'ls -la'
allow 'cat notes.md'
allow 'grep -rn "corpus" bin/'
allow 'ls -la ~/.callbutler/corpus && cat meta.json | grep rate' "chained ls && cat | grep"
allow 'afinfo rx.wav 2>/dev/null | grep -E "data format"' "2>/dev/null stripped; pipe to grep"
allow 'git status -sb && git log --oneline -3' "git status && git log"
allow 'git diff HEAD~1 --stat' "git diff"
allow 'git branch -a' "git branch (list form)"
allow 'git remote -v' "git remote -v"
allow 'git stash list' "git stash list"
allow 'git config --get user.name' "git config named-key read"
allow 'find . -name "*.wav" -newer ref' "find without action flags"
allow 'sed -n 5p file.sh' "sed pure-print, unquoted"
allow "sed -n '188,195p' bin/converse.sh" "sed pure-print, quoted range"
allow 'wc -l < input.txt' "input redirect stays a read"
allow 'grep -c x f >/dev/null && echo yes' ">/dev/null stripped"
allow 'ls missing 2>&1' "2>&1 stripped"
allow 'sysctl -n machdep.cpu.brand_string' "sysctl -n"
allow 'system_profiler SPHardwareDataType' "system_profiler"
allow 'defaults read com.apple.dock' "defaults read"
allow 'plutil -p Info.plist' "plutil -p"
allow 'jq -r .version package.json' "jq filter"
allow 'sort names.txt | uniq -c' "sort | uniq (no backslash)"
allow 'command -v jq' "command -v"
allow 'git log --oneline -3' "git log --oneline (must not trip the -o* write guard)"
allow 'git diff HEAD~1 --stat' "git diff with ~ (tilde is not rejected)"
allow 'file notes.md' "file in read mode still allowed"
allow 'tree -L 2 bin' "tree in read mode (no -o) still allowed"

echo "2) writes / mutations -> silent (would-be disasters, each must fall to the prompt)"
prompt 'rm -rf /tmp/x'
prompt 'ls && rm -rf /tmp/x' "one bad segment poisons the chain"
prompt 'echo hi > /tmp/f' "file redirect"
prompt 'echo hi >> /tmp/f' "append redirect"
prompt 'ls > out 2>&1' "redirect to a real file survives stripping"
prompt 'find . -delete'
prompt 'find . -exec rm {} \;' "find -exec"
prompt "sed -i '' s/a/b/ f" "sed -i"
prompt "sed -n '1p' -i f" "sed trailing -i after script"
prompt 'sort -o out in' "sort -o writes"
prompt 'uniq in out' "uniq's second positional writes"
prompt 'git push'
prompt 'git commit -m x'
prompt 'git branch newname' "git branch with a name arg creates"
prompt 'git config user.name x' "git config write form"
prompt 'git config --list' "git config dump can spill credential-bearing config"
prompt 'git config -l' "git config -l (same dump)"
prompt 'git config --get-regexp .' "git config --get-regexp dumps wholesale"
prompt 'git config --get credential.helper' "named key on the sensitive-term denylist"
prompt 'git log --output=/tmp/pwn' "git log --output writes"
prompt 'git stash pop'
prompt 'mv a b'; prompt 'cp a b'; prompt 'touch f'; prompt 'tee f'
prompt 'defaults write com.apple.dock x 1' "defaults write"
prompt 'plutil -convert xml1 f' "plutil non -p"
prompt 'sysctl -w kern.maxfiles=1' "sysctl -w"
prompt 'file -C -m magic.txt' "file -C compiles a .mgc (write via 'pure-read' binary)"
prompt 'file -Cm magic.txt' "file -Cm combined-short write flag"
prompt 'tree -o /tmp/out.txt' "tree -o writes the listing to a file"
prompt 'tree -o out.txt .' "tree -o <file> with a dir arg"

echo "2b) QUOTE/BACKSLASH-OBFUSCATED flags (the P0 class: shell strips the quote, a blocklist wouldn't) -> silent"
prompt "find . '-exec' rm {} +" "quoted -exec (P0)"
prompt "find . -'exec' rm {} +" "mid-quoted -'exec' (P0)"
prompt 'find . -exe\c rm {} +' "backslash-escaped flag (P0)"
prompt "find . '-delete'" "quoted -delete"
prompt "sort -'o' out in.txt" "quoted sort -o (P0)"
prompt 'sort -"o" out in.txt' "double-quoted sort -o"
prompt "rg --'pre' sh pat ." "quoted rg --pre (P0)"
prompt 'git log --"output"=/tmp/pwn' "quoted git --output (P0)"
prompt 'cat ~/.ss""h/id_""rsa' "empty-quote sensitive-path evasion (P0)"

echo "2c) unquoted write/exec flags the first pass missed -> silent"
prompt 'git grep --open-files-in-pager=touch foo' "git grep --open-files-in-pager (P0)"
prompt 'git grep -Otouch foo' "git grep -O<cmd> (P0)"
prompt 'git branch --set-upstream-to=origin/main' "git branch write flag (P0)"
prompt 'git branch --edit-description' "git branch --edit-description (P0)"
prompt 'git branch --unset-upstream' "git branch --unset-upstream"
prompt 'sort -S1 --compress-program=/tmp/x hugefile' "sort --compress-program exec (P0)"
prompt 'jq -n env' "jq env dump (P1)"
prompt 'jq -n import' "jq module read"
prompt 'date -s 2020-01-01' "date -s clock set"
prompt 'date 010112342020' "BSD bare date set-string"
prompt 'git -c core.pager=touch grep x' "git -c config/alias RCE"
prompt 'git -C /tmp status' "git -C (rejected, safe false-negative)"

echo "3) smuggling -> silent"
prompt 'cat $(rm -rf /tmp/x)' "command substitution"
prompt 'cat `rm -rf /tmp/x`' "backticks"
prompt 'cat <(rm x)' "process substitution"
prompt 'cat <<EOF
rm x
EOF' "heredoc"
prompt 'ls & rm x' "background job"
prompt './cat /etc/passwd' "relative-path argv0"
prompt '/tmp/ls' "absolute-path argv0"
prompt 'FOO=bar ls' "env-assignment prefix"
prompt 'bash -c "rm x"' "shell runner"
prompt 'eval rm x'; prompt 'xargs rm'
prompt 'curl https://example.com' "network binary"
prompt 'ssh host ls' "network binary (ssh)"
prompt "rg --pre 'rm -rf' pat f" "rg --pre executes"
prompt 'env' "env dump can carry secrets"
prompt 'for f in *; do cat "$f"; done' "shell loop (unparsed, fail-closed)"
prompt 'grep -E "a|b" f' "quoted pipe confuses the splitter (documented false-reject)"
prompt 'ls ${ touch x; }' "bash 5.3 funsub (\$ rejected globally)"
prompt 'echo hi > /dev/null/../../tmp/pwn' "/dev/null-traversal redirect is NOT a token-boundary strip"
prompt 'du -sh $HOME' "any \$ expansion (documented false-reject)"
prompt 'grep "\\bword" f' "any backslash (documented false-reject)"

echo "4) sensitive paths/terms -> silent even though the binary is read-only"
prompt 'cat ~/.ssh/id_rsa'
prompt 'cat .env'
prompt 'grep -r x ~/.aws'
prompt 'cat sip-mac.pass' ".pass file"
prompt 'grep api_token config.json' "token substring"
prompt 'cat CREDENTIALS.md' "case-insensitive"

echo "5) scope: only plan mode, only Bash"
prompt 'ls' "default mode" default
prompt 'ls' "acceptEdits mode" acceptEdits
prompt 'ls' "bypassPermissions mode" bypassPermissions
prompt 'ls' "empty mode (old host without the field)" ""
OUT=$(jq -cn '{permission_mode:"plan",tool_name:"Read",tool_input:{file_path:"/x"}}' | bash "$HOOK" 2>/dev/null); RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then PASS=$((PASS+1)); echo "ok   - prompt: non-Bash tool ignored"; else FAIL=$((FAIL+1)); echo "FAIL - non-Bash tool (rc=$RC out=$OUT)"; fi

echo "6) kill switch"
OUT=$(payload plan 'ls' | TALE_PLAN_APPROVE=0 bash "$HOOK" 2>/dev/null); RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then PASS=$((PASS+1)); echo "ok   - TALE_PLAN_APPROVE=0 disables"; else FAIL=$((FAIL+1)); echo "FAIL - kill switch (rc=$RC out=$OUT)"; fi

echo "7) fail-safe: garbage/empty stdin, broken jq -> exit 0, silent"
OUT=$(printf 'not json' | bash "$HOOK" 2>&1); RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then PASS=$((PASS+1)); echo "ok   - garbage stdin"; else FAIL=$((FAIL+1)); echo "FAIL - garbage stdin (rc=$RC out=$OUT)"; fi
OUT=$(printf '' | bash "$HOOK" 2>&1); RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then PASS=$((PASS+1)); echo "ok   - empty stdin"; else FAIL=$((FAIL+1)); echo "FAIL - empty stdin (rc=$RC out=$OUT)"; fi
STUB=$(mktemp -d); printf '#!/bin/sh\nexit 1\n' > "$STUB/jq"; chmod +x "$STUB/jq"
OUT=$(payload plan 'ls' | PATH="$STUB:/usr/bin:/bin" bash "$HOOK" 2>&1); RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then PASS=$((PASS+1)); echo "ok   - broken jq"; else FAIL=$((FAIL+1)); echo "FAIL - broken jq (rc=$RC out=$OUT)"; fi
rm -rf "$STUB"

echo "8) allow output is well-formed for the harness"
OUT=$(payload plan 'ls && cat f' | bash "$HOOK" 2>/dev/null)
ok8=1
printf '%s' "$OUT" | jq -e '.hookSpecificOutput.hookEventName=="PreToolUse"' >/dev/null 2>&1 || ok8=0
printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("ls") and test("cat")' >/dev/null 2>&1 || ok8=0
if [ "$ok8" = 1 ]; then PASS=$((PASS+1)); echo "ok   - JSON shape + reason names the binaries"; else FAIL=$((FAIL+1)); echo "FAIL - JSON shape (out=$OUT)"; fi

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
