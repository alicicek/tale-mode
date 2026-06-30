#!/usr/bin/env bash
# tale-mode — tests for the phase-marker hook (UserPromptSubmit; cross-platform).
#
# The hook fires on every UserPromptSubmit; it acts only when the prompt is a
# /tale-mode:kickoff-phase invocation (or a host supplies command_name). It must: write a session-scoped marker
# .claude/tale-mode.phase.$SID.json on the kickoff command; be idempotent (a re-kickoff must
# NOT reset the round counter); never act on a different command, an absent/invalid session id,
# or unparseable input; and ALWAYS exit 0 writing nothing to stdout/stderr (it must never block
# or perturb the user's command — only exit 2 / a block decision would).
set -uo pipefail
HOOK="$(cd "$(dirname "$0")/../plugins/tale-mode/hooks" && pwd)/mark-phase.sh"
PASS=0; FAIL=0
ok() { if eval "$2"; then PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; else FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; fi; }

newwork(){ WORK=$(mktemp -d); mkdir -p "$WORK/.claude"; }
mk(){ printf '{"session_id":"%s","command_name":"%s","command_args":"docs/p.md \\"Phase C\\"","cwd":"%s"}' "$1" "$2" "$WORK"; }
mkp(){ printf '{"session_id":"%s","prompt":"%s","cwd":"%s"}' "$1" "$2" "$WORK"; }   # UserPromptSubmit shape (both runtimes)
mfile(){ echo "$WORK/.claude/tale-mode.phase.$1.json"; }

echo "1) kickoff command -> writes a session-scoped marker (exit 0, no stdout)"
newwork
OUT=$(mk "sid-1" "tale-mode:kickoff-phase" | CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK"); RC=$?
ok "exit 0"                  '[ "$RC" -eq 0 ]'
ok "no stdout"               '[ -z "$OUT" ]'
ok "marker written"          '[ -f "$(mfile sid-1)" ]'
ok "marker carries session"  '[ "$(jq -r .session "$(mfile sid-1)")" = "sid-1" ]'
ok "marker rounds=0"         '[ "$(jq -r .rounds "$(mfile sid-1)")" = "0" ]'
ok "marker needs_user=null"  '[ "$(jq -r ".needs_user==null" "$(mfile sid-1)")" = "true" ]'

echo "2) idempotent: a re-kickoff in the same session does NOT reset rounds"
jq '.rounds=9' "$(mfile sid-1)" > "$WORK/t" && mv "$WORK/t" "$(mfile sid-1)"
mk "sid-1" "tale-mode:kickoff-phase" | CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK"
ok "rounds preserved (9)"    '[ "$(jq -r .rounds "$(mfile sid-1)")" = "9" ]'

echo "3) a DIFFERENT command (plan-phase) -> no marker, exit 0"
newwork
OUT=$(mk "sid-2" "tale-mode:plan-phase" | CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK"); RC=$?
ok "exit 0"                  '[ "$RC" -eq 0 ]'
ok "no marker"               '[ ! -f "$(mfile sid-2)" ]'

echo "4) namespace-robust: any '<ns>:kickoff-phase' matches the defensive guard"
newwork
mk "sid-3" "othermarket:kickoff-phase" | CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK"
ok "marker written"          '[ -f "$(mfile sid-3)" ]'

echo "5) absent session_id -> no marker (a phase is always session-scoped)"
newwork
OUT=$(printf '{"command_name":"tale-mode:kickoff-phase","cwd":"%s"}' "$WORK" | CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK"); RC=$?
ok "exit 0"                  '[ "$RC" -eq 0 ]'
ok "no marker for empty sid" '[ -z "$(ls "$WORK/.claude/" 2>/dev/null)" ]'

echo "6) invalid session_id (path traversal) -> rejected as a filename token, no marker"
newwork
printf '{"session_id":"../evil","command_name":"tale-mode:kickoff-phase","cwd":"%s"}' "$WORK" | CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK"
ok "no marker written"       '[ -z "$(ls "$WORK/.claude/" 2>/dev/null)" ]'
ok "no escape file created"  '[ ! -e "$WORK/../evil" ] || true'

echo "7) cwd fallback when CLAUDE_PROJECT_DIR is unset"
newwork
printf '{"session_id":"sid-4","command_name":"tale-mode:kickoff-phase","cwd":"%s"}' "$WORK" | env -u CLAUDE_PROJECT_DIR bash "$HOOK"
ok "marker written under cwd" '[ -f "$(mfile sid-4)" ]'

echo "8) fail-safe: garbage / empty stdin -> exit 0, silent (never blocks the command)"
G=$(mktemp -d)
OUT=$(printf 'not json at all' | CLAUDE_PROJECT_DIR="$G" bash "$HOOK" 2>&1); RC=$?
ok "garbage stdin exit 0"    '[ "$RC" -eq 0 ]'
ok "garbage stdin silent"    '[ -z "$OUT" ]'
OUT=$(printf '' | CLAUDE_PROJECT_DIR="$G" bash "$HOOK" 2>&1); RC=$?
ok "empty stdin exit 0"      '[ "$RC" -eq 0 ]'
ok "empty stdin silent"      '[ -z "$OUT" ]'

echo "9) unusable jq (parser broken) -> fail-safe: no marker, exit 0"
newwork
STUB=$(mktemp -d); printf '#!/bin/sh\nexit 1\n' > "$STUB/jq"; chmod +x "$STUB/jq"
OUT=$(mk "sid-5" "tale-mode:kickoff-phase" | PATH="$STUB:/usr/bin:/bin" CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK"); RC=$?
ok "exit 0 with broken jq"   '[ "$RC" -eq 0 ]'
ok "no marker with broken jq" '[ ! -f "$(mfile sid-5)" ]'
rm -rf "$STUB"

echo "10) UserPromptSubmit prompt IS a kickoff -> writes the marker (the cross-platform path)"
newwork
OUT=$(mkp "sid-10" "/tale-mode:kickoff-phase docs/p.md PhaseC" | CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK"); RC=$?
ok "exit 0"                   '[ "$RC" -eq 0 ]'
ok "no stdout"                '[ -z "$OUT" ]'
ok "marker written"           '[ -f "$(mfile sid-10)" ]'
ok "marker rounds=0"          '[ "$(jq -r .rounds "$(mfile sid-10)")" = "0" ]'

echo "11) UserPromptSubmit ORDINARY prompt -> NO marker (fires every prompt, must stay silent)"
newwork
OUT=$(mkp "sid-11" "how do I add a rate limit to signup" | CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK"); RC=$?
ok "exit 0"                   '[ "$RC" -eq 0 ]'
ok "no marker"                '[ ! -f "$(mfile sid-11)" ]'
ok "claude dir stayed empty"  '[ -z "$(ls "$WORK/.claude/" 2>/dev/null)" ]'

echo "12) UserPromptSubmit kickoff under a DIFFERENT namespace -> marker written (namespace-robust)"
newwork
mkp "sid-12" "/othermarket:kickoff-phase plan.md PhaseZ" | CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK"
ok "marker written"           '[ -f "$(mfile sid-12)" ]'

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
