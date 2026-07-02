#!/usr/bin/env bash
# tale-mode-governor — tests for the unified Layer-2 governor hook (governor.sh, v2).
#
# BOTH escalation binaries are stubbed: fake `claude` and `codex` on PATH that record their
# argv + env (+ stdin, for claude, since the prompt travels on stdin there) and reply with a
# canned reviewer answer. That lets us assert the script's ENTIRE contract hermetically:
# every guard exits silent WITHOUT spawning (sentinel, kill switches, host detect, opt-in,
# no-goal, rounds!=2), and each host's spawn path passes its load-bearing flags (CC:
# -p/--model/--tools read-only set; Codex: -s read-only/--ephemeral), exports the recursion
# sentinel, and surfaces a finding as an ADVISORY systemMessage — never a decision. The
# live behaviors the flags rely on were probed for real (docs/codex-governor-spike.md).
set -uo pipefail
HOOK="$(cd "$(dirname "$0")/../plugins/tale-mode-governor/hooks" && pwd)/governor.sh"
PASS=0; FAIL=0
ok() { if eval "$2"; then PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; else FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; fi; }

# --- the stubs -------------------------------------------------------------------------------
STUB=$(mktemp -d)
cat > "$STUB/codex" <<'EOF'
#!/bin/sh
echo "$@" > "${STUB_LOG:?}/cx-argv.txt"
env | grep '^TALE_GOVERNOR_ACTIVE=' > "${STUB_LOG}/cx-env.txt" 2>/dev/null || true
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
[ -n "$out" ] && printf '%s' "${STUB_REPLY:-NOTHING}" > "$out"
exit 0
EOF
cat > "$STUB/claude" <<'EOF'
#!/bin/sh
echo "$@" > "${STUB_LOG:?}/cc-argv.txt"
env | grep '^TALE_GOVERNOR_ACTIVE=' > "${STUB_LOG}/cc-env.txt" 2>/dev/null || true
cat > "${STUB_LOG}/cc-stdin.txt" 2>/dev/null || true
printf '%s' "${STUB_REPLY:-NOTHING}"
exit 0
EOF
chmod +x "$STUB/codex" "$STUB/claude"
SLOG=$(mktemp -d)
# jq may live outside /usr/bin (e.g. Homebrew) — keep it reachable or guard cases pass vacuously.
JQD=$(dirname "$(command -v jq)")
TPATH="$STUB:$JQD:/usr/bin:/bin"
CLEANDIRS="$STUB $SLOG"
trap 'rm -rf $CLEANDIRS' EXIT

newwork()  { WORK=$(mktemp -d); mkdir -p "$WORK/.claude"; HM=$(mktemp -d); CLEANDIRS="$CLEANDIRS $WORK $HM"; rm -f "$SLOG"/cx-*.txt "$SLOG"/cc-*.txt; }
goal()     { printf '{"goal":"g","check":"false","rounds":%s,"max_rounds":25}' "${1:-3}" > "$WORK/.claude/active-goal.json"; }
# Codex-shaped run: PLUGIN_ROOT set, CLAUDE_PROJECT_DIR absent, opt-in via env
cxrun()    { OUT=$(printf '{"session_id":"s1","cwd":"%s","hook_event_name":"Stop"}' "$WORK" \
               | env -u CLAUDE_PROJECT_DIR -u TALE_GOVERNOR_ACTIVE PLUGIN_ROOT=/fake/plugin HOME="$HM" \
                 TALE_ALLOW_CWD_ROOT=1 STUB_LOG="$SLOG" STUB_REPLY="${STUB_REPLY:-NOTHING}" \
                 PATH="$TPATH" bash "$HOOK" 2>&1); RC=$?; }
# Claude-Code-shaped run: CLAUDE_PROJECT_DIR set (the trusted root), PLUGIN_ROOT absent
ccrun()    { OUT=$(printf '{"session_id":"s1","cwd":"%s","hook_event_name":"Stop"}' "$WORK" \
               | env -u PLUGIN_ROOT -u TALE_GOVERNOR_ACTIVE CLAUDE_PROJECT_DIR="$WORK" HOME="$HM" \
                 STUB_LOG="$SLOG" STUB_REPLY="${STUB_REPLY:-NOTHING}" \
                 PATH="$TPATH" bash "$HOOK" 2>&1); RC=$?; }
cx_spawned(){ [ -f "$SLOG/cx-argv.txt" ]; }
cc_spawned(){ [ -f "$SLOG/cc-argv.txt" ]; }

echo "1) recursion sentinel set -> instant silent no-op, nothing spawned (either host shape)"
newwork; goal 2
OUT=$(printf '{"cwd":"%s"}' "$WORK" | env PLUGIN_ROOT=/fake TALE_GOVERNOR_ACTIVE=1 STUB_LOG="$SLOG" PATH="$TPATH" bash "$HOOK" 2>&1); RC=$?
ok "exit 0 + silent"        '[ "$RC" -eq 0 ] && [ -z "$OUT" ]'
ok "nothing spawned"        '! cx_spawned && ! cc_spawned'
OUT=$(printf '{"cwd":"%s"}' "$WORK" | env CLAUDE_PROJECT_DIR="$WORK" TALE_GOVERNOR_ACTIVE=1 STUB_LOG="$SLOG" PATH="$TPATH" bash "$HOOK" 2>&1); RC=$?
ok "CC shape too: exit 0 + silent, not spawned" '[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ! cc_spawned'

echo "2) kill switches: TALE_GOVERNOR=0 and the v1 TALE_CODEX_GOVERNOR=0 both silence it"
newwork; goal 2
OUT=$(printf '{"session_id":"s1","cwd":"%s"}' "$WORK" | env -u PLUGIN_ROOT CLAUDE_PROJECT_DIR="$WORK" TALE_GOVERNOR=0 STUB_LOG="$SLOG" PATH="$TPATH" bash "$HOOK" 2>&1); RC=$?
ok "TALE_GOVERNOR=0: silent, not spawned"        '[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ! cc_spawned'
OUT=$(printf '{"session_id":"s1","cwd":"%s"}' "$WORK" | env -u CLAUDE_PROJECT_DIR PLUGIN_ROOT=/fake TALE_CODEX_GOVERNOR=0 TALE_ALLOW_CWD_ROOT=1 STUB_LOG="$SLOG" PATH="$TPATH" bash "$HOOK" 2>&1); RC=$?
ok "TALE_CODEX_GOVERNOR=0 (back-compat): silent" '[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ! cx_spawned'
# ...but the legacy switch keeps its v1 SCOPE: it must NOT silence the Claude Code side.
newwork; goal 2
OUT=$(printf '{"session_id":"s1","cwd":"%s"}' "$WORK" | env -u PLUGIN_ROOT -u TALE_GOVERNOR_ACTIVE CLAUDE_PROJECT_DIR="$WORK" TALE_CODEX_GOVERNOR=0 STUB_LOG="$SLOG" STUB_REPLY="finding z" PATH="$TPATH" bash "$HOOK" 2>&1); RC=$?
ok "TALE_CODEX_GOVERNOR=0 does NOT kill CC (v1 scope preserved)" 'printf "%s" "$OUT" | jq -e ".systemMessage" >/dev/null && cc_spawned'

echo "3) neither host signature (no CLAUDE_PROJECT_DIR, no PLUGIN_ROOT) -> silent no-op"
newwork; goal 2
OUT=$(printf '{"session_id":"s1","cwd":"%s"}' "$WORK" | env -u CLAUDE_PROJECT_DIR -u PLUGIN_ROOT STUB_LOG="$SLOG" PATH="$TPATH" bash "$HOOK" 2>&1); RC=$?
ok "exit 0 + silent, nothing spawned" '[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ! cx_spawned && ! cc_spawned'

echo "4) Codex: NO user opt-in (no env, clean HOME) -> root never resolves -> silent"
newwork; goal 2
OUT=$(printf '{"session_id":"s1","cwd":"%s"}' "$WORK" | env -u CLAUDE_PROJECT_DIR -u TALE_ALLOW_CWD_ROOT PLUGIN_ROOT=/fake HOME="$HM" STUB_LOG="$SLOG" PATH="$TPATH" bash "$HOOK" 2>&1); RC=$?
ok "exit 0 + silent, not spawned" '[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ! cx_spawned'

echo "5) idle guarantees: no goal-file -> silent; rounds=1 -> silent (both hosts, zero spawns)"
newwork; ccrun
ok "CC, no goal: silent, not spawned"    '[ -z "$OUT" ] && ! cc_spawned'
newwork; goal 1; ccrun
ok "CC, rounds=1: silent, not spawned"   '[ -z "$OUT" ] && ! cc_spawned'
newwork; cxrun
ok "Codex, no goal: silent, not spawned" '[ -z "$OUT" ] && ! cx_spawned'
newwork; goal 1; cxrun
ok "Codex, rounds=1: silent, not spawned" '[ -z "$OUT" ] && ! cx_spawned'

echo "6) CC STUCK (rounds==2) + a finding -> advisory systemMessage, correct claude -p contract"
newwork; goal 2; STUB_REPLY="the plan says X is deploy-only; stop forcing it locally (plan.md)" ccrun
ok "exit 0"                              '[ "$RC" -eq 0 ]'
ok "emits a systemMessage"               'printf "%s" "$OUT" | jq -e ".systemMessage" >/dev/null'
ok "message carries the finding"         'printf "%s" "$OUT" | jq -r ".systemMessage" | grep -q "deploy-only"'
ok "NEVER a decision (advisory only)"    '! printf "%s" "$OUT" | jq -e ".decision" >/dev/null 2>&1'
ok "spawned with -p"                     'grep -q -- "-p" "$SLOG/cc-argv.txt"'
ok "pinned model claude-sonnet-4-6"      'grep -q -- "--model claude-sonnet-4-6" "$SLOG/cc-argv.txt"'
ok "read-only tool set (Read Grep Glob)" 'grep -q -- "--tools Read Grep Glob" "$SLOG/cc-argv.txt"'
ok "MCP stripped (--strict-mcp-config)"  'grep -q -- "--strict-mcp-config" "$SLOG/cc-argv.txt"'
ok "prompt arrived on stdin"             'grep -q "FAILED the same goal" "$SLOG/cc-stdin.txt"'
ok "recursion sentinel exported"         'grep -q "^TALE_GOVERNOR_ACTIVE=1$" "$SLOG/cc-env.txt"'

echo "7) CC fires ONCE per stuck goal: rounds past 2 -> silent, NOT spawned again"
newwork; goal 5; ccrun
ok "rounds=5: exit 0 + silent, not spawned" '[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ! cc_spawned'

echo "8) CC model override: TALE_GOVERNOR_MODEL reaches the argv"
newwork; goal 2
OUT=$(printf '{"session_id":"s1","cwd":"%s"}' "$WORK" \
   | env -u PLUGIN_ROOT -u TALE_GOVERNOR_ACTIVE CLAUDE_PROJECT_DIR="$WORK" TALE_GOVERNOR_MODEL=claude-haiku-4-5 \
     STUB_LOG="$SLOG" STUB_REPLY="finding x" PATH="$TPATH" bash "$HOOK" 2>&1); RC=$?
ok "override model in argv"  'grep -q -- "--model claude-haiku-4-5" "$SLOG/cc-argv.txt"'

echo "9) Codex STUCK (rounds==2) + a finding -> advisory systemMessage, correct codex exec contract"
newwork; goal 2; STUB_REPLY="foundation missing: src/wire.ts never imports the adapter" cxrun
ok "emits a systemMessage"               'printf "%s" "$OUT" | jq -e ".systemMessage" >/dev/null'
ok "NEVER a decision"                    '! printf "%s" "$OUT" | jq -e ".decision" >/dev/null 2>&1'
ok "spawned with -s read-only"           'grep -q -- "-s read-only" "$SLOG/cx-argv.txt"'
ok "spawned with --ephemeral"            'grep -q -- "--ephemeral" "$SLOG/cx-argv.txt"'
ok "recursion sentinel exported"         'grep -q "^TALE_GOVERNOR_ACTIVE=1$" "$SLOG/cx-env.txt"'

echo "10) Codex fires ONCE per stuck goal: rounds past 2 -> silent, NOT spawned"
newwork; goal 5; cxrun
ok "rounds=5: silent, not spawned"       '[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ! cx_spawned'

echo "11) reviewer finds NOTHING -> stays silent on both hosts (never advise on vague doubt)"
newwork; goal 2; STUB_REPLY="NOTHING" ccrun
ok "CC: exit 0 + silent, but claude WAS consulted"   '[ "$RC" -eq 0 ] && [ -z "$OUT" ] && cc_spawned'
newwork; goal 2; STUB_REPLY="NOTHING" cxrun
ok "Codex: exit 0 + silent, but codex WAS consulted" '[ "$RC" -eq 0 ] && [ -z "$OUT" ] && cx_spawned'

echo "12) garbage stdin: CC still fires via the trusted-env root + legacy goal-file (stdin is not load-bearing there); Codex cannot resolve a root -> never spawns"
newwork; goal 2
OUT=$(printf 'not json' | env -u PLUGIN_ROOT -u TALE_GOVERNOR_ACTIVE CLAUDE_PROJECT_DIR="$WORK" STUB_LOG="$SLOG" STUB_REPLY="real finding y" PATH="$TPATH" bash "$HOOK" 2>&1); RC=$?
ok "CC + garbage stdin: exit 0, FIRES via legacy fallback" '[ "$RC" -eq 0 ] && printf "%s" "$OUT" | jq -e ".systemMessage" >/dev/null && cc_spawned'
newwork; goal 2
OUT=$(printf 'not json' | env -u CLAUDE_PROJECT_DIR -u TALE_GOVERNOR_ACTIVE PLUGIN_ROOT=/fake TALE_ALLOW_CWD_ROOT=1 STUB_LOG="$SLOG" STUB_REPLY="real finding y" PATH="$TPATH" bash "$HOOK" 2>&1); RC=$?
ok "Codex + garbage stdin: root unresolvable -> silent, NOT spawned" '[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ! cx_spawned'
NOBIN=$(mktemp -d); CLEANDIRS="$CLEANDIRS $NOBIN"; for b in bash cat jq sed tr head mktemp rm grep env dirname; do p=$(command -v $b) && ln -s "$p" "$NOBIN/$b"; done
newwork; goal 2
OUT=$(printf '{"session_id":"s1","cwd":"%s"}' "$WORK" | env -u PLUGIN_ROOT CLAUDE_PROJECT_DIR="$WORK" PATH="$NOBIN" bash "$HOOK" 2>&1); RC=$?
ok "no claude on PATH (CC): exit 0 + silent" '[ "$RC" -eq 0 ] && [ -z "$OUT" ]'
OUT=$(printf '{"session_id":"s1","cwd":"%s"}' "$WORK" | env -u CLAUDE_PROJECT_DIR PLUGIN_ROOT=/fake TALE_ALLOW_CWD_ROOT=1 PATH="$NOBIN" bash "$HOOK" 2>&1); RC=$?
ok "no codex on PATH (Codex): exit 0 + silent" '[ "$RC" -eq 0 ] && [ -z "$OUT" ]'

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
