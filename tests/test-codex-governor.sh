#!/usr/bin/env bash
# tale-mode-governor — tests for the Codex governor hook (codex-governor.sh).
#
# The real `codex` is stubbed: a fake binary on PATH that records its argv + env and writes a
# canned reviewer reply to the `-o` file. That lets us assert the script's ENTIRE contract
# hermetically: every guard exits silent WITHOUT spawning (sentinel, platform, kill switch,
# opt-in, no-goal, rounds<2), and the spawn path passes the load-bearing flags (-s read-only,
# --ephemeral), exports the recursion sentinel, and surfaces a finding as an ADVISORY
# systemMessage — never a decision. The live-Codex behaviors these flags rely on were probed
# for real on 2026-07-01 (see docs/codex-governor-spike.md).
set -uo pipefail
HOOK="$(cd "$(dirname "$0")/../plugins/tale-mode-governor/hooks" && pwd)/codex-governor.sh"
PASS=0; FAIL=0
ok() { if eval "$2"; then PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; else FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; fi; }

# --- the codex stub -------------------------------------------------------------------------
STUB=$(mktemp -d)
cat > "$STUB/codex" <<'EOF'
#!/bin/sh
# fake codex: record argv + the sentinel, honor -o <file>, reply with $STUB_REPLY
echo "$@" > "${STUB_LOG:?}/argv.txt"
env | grep '^TALE_GOVERNOR_ACTIVE=' > "${STUB_LOG}/env.txt" 2>/dev/null || true
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
[ -n "$out" ] && printf '%s' "${STUB_REPLY:-NOTHING}" > "$out"
exit 0
EOF
chmod +x "$STUB/codex"
SLOG=$(mktemp -d)
# jq may live outside /usr/bin (e.g. Homebrew) — keep it reachable or guard cases pass vacuously.
JQD=$(dirname "$(command -v jq)")
TPATH="$STUB:$JQD:/usr/bin:/bin"
CLEANDIRS="$STUB $SLOG"
trap 'rm -rf $CLEANDIRS' EXIT

newwork() { WORK=$(mktemp -d); mkdir -p "$WORK/.claude"; HM=$(mktemp -d); CLEANDIRS="$CLEANDIRS $WORK $HM"; rm -f "$SLOG"/argv.txt "$SLOG"/env.txt; }
goal()    { printf '{"goal":"g","check":"false","rounds":%s,"max_rounds":25}' "${1:-3}" > "$WORK/.claude/active-goal.json"; }
# run with a Codex-shaped environment: PLUGIN_ROOT set, CLAUDE_PROJECT_DIR absent, opt-in via env
grun()    { OUT=$(printf '{"session_id":"s1","cwd":"%s","hook_event_name":"Stop"}' "$WORK" \
              | env -u CLAUDE_PROJECT_DIR -u TALE_GOVERNOR_ACTIVE PLUGIN_ROOT=/fake/plugin HOME="$HM" \
                TALE_ALLOW_CWD_ROOT=1 STUB_LOG="$SLOG" STUB_REPLY="${STUB_REPLY:-NOTHING}" \
                PATH="$TPATH" bash "$HOOK" 2>&1); RC=$?; }
spawned() { [ -f "$SLOG/argv.txt" ]; }

echo "1) recursion sentinel set -> instant silent no-op, codex NOT spawned"
newwork; goal 5
OUT=$(printf '{"cwd":"%s"}' "$WORK" | env PLUGIN_ROOT=/fake TALE_GOVERNOR_ACTIVE=1 STUB_LOG="$SLOG" PATH="$TPATH" bash "$HOOK" 2>&1); RC=$?
ok "exit 0"              '[ "$RC" -eq 0 ]'
ok "silent"              '[ -z "$OUT" ]'
ok "codex NOT spawned"   '! spawned'

echo "2) Claude Code shape (CLAUDE_PROJECT_DIR set) -> silent no-op (the agent hook owns CC)"
newwork; goal 5
OUT=$(printf '{"cwd":"%s"}' "$WORK" | env CLAUDE_PROJECT_DIR="$WORK" PLUGIN_ROOT=/fake STUB_LOG="$SLOG" PATH="$TPATH" bash "$HOOK" 2>&1); RC=$?
ok "exit 0 + silent"     '[ "$RC" -eq 0 ] && [ -z "$OUT" ]'
ok "codex NOT spawned"   '! spawned'

echo "3) PLUGIN_ROOT unset (not a Codex plugin-hook host) -> silent no-op"
newwork; goal 5
OUT=$(printf '{"cwd":"%s"}' "$WORK" | env -u CLAUDE_PROJECT_DIR -u PLUGIN_ROOT STUB_LOG="$SLOG" PATH="$TPATH" bash "$HOOK" 2>&1); RC=$?
ok "exit 0 + silent"     '[ "$RC" -eq 0 ] && [ -z "$OUT" ]'
ok "codex NOT spawned"   '! spawned'

echo "4) kill switch TALE_CODEX_GOVERNOR=0 -> silent no-op"
newwork; goal 5
OUT=$(printf '{"session_id":"s1","cwd":"%s"}' "$WORK" | env -u CLAUDE_PROJECT_DIR PLUGIN_ROOT=/fake TALE_CODEX_GOVERNOR=0 TALE_ALLOW_CWD_ROOT=1 STUB_LOG="$SLOG" PATH="$TPATH" bash "$HOOK" 2>&1); RC=$?
ok "exit 0 + silent"     '[ "$RC" -eq 0 ] && [ -z "$OUT" ]'
ok "codex NOT spawned"   '! spawned'

echo "5) NO user opt-in (no env, clean HOME) -> root never resolves -> silent, not spawned"
newwork; goal 5
OUT=$(printf '{"session_id":"s1","cwd":"%s"}' "$WORK" | env -u CLAUDE_PROJECT_DIR -u TALE_ALLOW_CWD_ROOT PLUGIN_ROOT=/fake HOME="$HM" STUB_LOG="$SLOG" PATH="$TPATH" bash "$HOOK" 2>&1); RC=$?
ok "exit 0 + silent"     '[ "$RC" -eq 0 ] && [ -z "$OUT" ]'
ok "codex NOT spawned"   '! spawned'

echo "6) no goal-file -> silent; rounds<2 -> silent (L1 owns early rounds)"
newwork; grun
ok "no goal: silent, not spawned"    '[ -z "$OUT" ] && ! spawned'
newwork; goal 1; grun
ok "rounds=1: silent, not spawned"   '[ -z "$OUT" ] && ! spawned'

echo "7) STUCK (rounds==2, the two-strike moment) + a concrete finding -> advisory systemMessage, correct spawn contract"
newwork; goal 2; STUB_REPLY="the plan says X is deploy-only; stop forcing it locally (plan.md)" grun
ok "exit 0"                             '[ "$RC" -eq 0 ]'
ok "emits a systemMessage"              'printf "%s" "$OUT" | jq -e ".systemMessage" >/dev/null'
ok "message carries the finding"        'printf "%s" "$OUT" | jq -r ".systemMessage" | grep -q "deploy-only"'
ok "NEVER a decision (advisory only)"   '! printf "%s" "$OUT" | jq -e ".decision" >/dev/null 2>&1'
ok "spawned with -s read-only"          'grep -q -- "-s read-only" "$SLOG/argv.txt"'
ok "spawned with --ephemeral"           'grep -q -- "--ephemeral" "$SLOG/argv.txt"'
ok "recursion sentinel exported to the child" 'grep -q "^TALE_GOVERNOR_ACTIVE=1$" "$SLOG/env.txt"'

echo "7b) fires ONCE per stuck goal: rounds past 2 (already governed) -> silent, NOT spawned again"
newwork; goal 5; grun
ok "rounds=5: exit 0 + silent"  '[ "$RC" -eq 0 ] && [ -z "$OUT" ]'
ok "codex NOT spawned again"    '! spawned'

echo "8) reviewer finds NOTHING -> stays silent (never block on vague doubt)"
newwork; goal 2; STUB_REPLY="NOTHING" grun
ok "exit 0 + silent"     '[ "$RC" -eq 0 ] && [ -z "$OUT" ]'
ok "codex WAS consulted" 'spawned'

echo "9) fail-safe: garbage stdin / codex absent -> exit 0, silent"
newwork; goal 5
OUT=$(printf 'not json' | env -u CLAUDE_PROJECT_DIR PLUGIN_ROOT=/fake TALE_ALLOW_CWD_ROOT=1 STUB_LOG="$SLOG" PATH="$TPATH" bash "$HOOK" 2>&1); RC=$?
ok "garbage stdin: exit 0 + silent"  '[ "$RC" -eq 0 ] && [ -z "$OUT" ]'
newwork; goal 5
NOCODEX=$(mktemp -d); CLEANDIRS="$CLEANDIRS $NOCODEX"; for b in bash cat jq sed tr tail mktemp rm grep env; do p=$(command -v $b) && ln -s "$p" "$NOCODEX/$b"; done
OUT=$(printf '{"session_id":"s1","cwd":"%s"}' "$WORK" | env -u CLAUDE_PROJECT_DIR PLUGIN_ROOT=/fake TALE_ALLOW_CWD_ROOT=1 PATH="$NOCODEX" bash "$HOOK" 2>&1); RC=$?
ok "no codex on PATH: exit 0 + silent" '[ "$RC" -eq 0 ] && [ -z "$OUT" ]'
rm -rf "$NOCODEX"

rm -rf "$STUB" "$SLOG"
printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
