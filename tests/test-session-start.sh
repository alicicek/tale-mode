#!/usr/bin/env bash
# tale-mode — tests for the SessionStart discipline-injection hook.
#
# The script runs on EVERY session start, so it must be bullet-proof: emit the core
# disciplines, exit 0 on any input, and depend on nothing beyond `cat` (a missing tool
# must never break a session). These tests assert exactly that.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/../plugins/tale-mode/hooks" && pwd)/session-start.sh"
PASS=0; FAIL=0
ok() { if eval "$2"; then PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; else FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; fi; }

# 1. Empty stdin -> exits 0 and emits something.
OUT=$(printf '' | bash "$HOOK"); RC=$?
ok "exits 0 on empty stdin"            '[ "$RC" -eq 0 ]'
ok "emits non-empty output"            '[ -n "$OUT" ]'

# 2. Carries each of the three core disciplines (distilled from SKILL.md).
ok "injects verify-against-source"     'printf "%s" "$OUT" | grep -qi "ground truth"'
ok "injects foundation-first"          'printf "%s" "$OUT" | grep -qi "foundation-first"'
ok "injects two-strike rule"           'printf "%s" "$OUT" | grep -qi "two-strike"'

# 3. A realistic SessionStart JSON payload on stdin must not choke it (e.g. compact).
OUT2=$(printf '%s' '{"session_id":"s1","source":"compact","hook_event_name":"SessionStart"}' | bash "$HOOK"); RC2=$?
ok "exits 0 on JSON stdin (compact)"   '[ "$RC2" -eq 0 ]'

# 4. No external-tool dependency: it must run under a bare environment and still emit.
OUT3=$(env -i PATH=/usr/bin:/bin bash "$HOOK" </dev/null); RC3=$?
ok "exits 0 under a bare environment"  '[ "$RC3" -eq 0 ]'
ok "still emits under a bare env"      '[ -n "$OUT3" ]'

# 5. No external-parser dependency: shadow every parser the script could lean on
#    with failing stubs; it must still emit and exit 0 (it should use none of them).
STUB=$(mktemp -d)
for t in jq python python3 node perl ruby; do printf '#!/bin/sh\nexit 1\n' > "$STUB/$t"; chmod +x "$STUB/$t"; done
OUT4=$(PATH="$STUB:/usr/bin:/bin" bash "$HOOK" </dev/null); RC4=$?
ok "exits 0 with parsers shadowed/broken" '[ "$RC4" -eq 0 ]'
ok "still emits with parsers shadowed"    '[ -n "$OUT4" ]'
rm -rf "$STUB"

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
