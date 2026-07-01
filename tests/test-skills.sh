#!/usr/bin/env bash
# tale-mode — structural lint for the Markdown-only surfaces (skills + output style).
#
# `claude plugin validate` does NOT parse skill/output-style frontmatter, so a malformed
# name/description — or safety-critical text silently drifting out of a skill — would ship
# without any gate noticing (Phase A deferral 4b). These are deterministic greps, not prose
# review: they assert (1) each SKILL.md declares well-formed frontmatter whose name matches its
# directory, (2) the helper skills keep their explicit-invocation tuning (they must not
# auto-trigger) and their user-only-grant guardrails, and (3) the pending-marker filename the
# kickoff-phase skill tells the agent to write is the SAME string the Stop hook adopts — the
# one cross-file contract here that a rename would silently break.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUG="$ROOT/plugins/tale-mode"
PASS=0; FAIL=0
ok() { if eval "$2"; then PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; else FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; fi; }

echo "1) every skill dir ships a SKILL.md with well-formed frontmatter (name == dir, description present)"
for d in "$PLUG"/skills/*/; do
  n=$(basename "$d"); f="$d/SKILL.md"
  ok "$n: SKILL.md exists"                 '[ -f "$f" ]'
  ok "$n: opens with ---"                  '[ "$(head -n1 "$f")" = "---" ]'
  ok "$n: frontmatter closes"              '[ "$(sed -n "2,30p" "$f" | grep -c "^---$")" -ge 1 ]'
  ok "$n: name matches directory"          'grep -qE "^name: ${n}$" "$f"'
  ok "$n: has a description"               'grep -qE "^description:" "$f"'
done

echo "2) helper skills are tuned NOT to auto-trigger (explicit-invocation wording in the description)"
for n in trust end-phase seed-gates; do
  ok "$n: description says invoke only on an explicit ask" \
     'grep -q "ONLY when the user explicitly asks" "$PLUG/skills/$n/SKILL.md"'
done

echo "3) user-only-grant guardrails present (the agent must never write either grant file)"
ok "trust: documents the Codex cwd-root opt-in file"      'grep -q -- "~/.tale-mode-allow-cwd-root" "$PLUG/skills/trust/SKILL.md"'
ok "trust: documents the committed-gate trust store"      'grep -q -- "~/.claude/tale-mode-trust" "$PLUG/skills/trust/SKILL.md"'
ok "trust: forbids the agent writing the grants"          'grep -q "NEVER write" "$PLUG/skills/trust/SKILL.md"'
ok "seed-gates: suggest-only framing"                     'grep -qi "suggestions only" "$PLUG/skills/seed-gates/SKILL.md"'
ok "seed-gates: never touches the trust store"            'grep -q "touch the trust store" "$PLUG/skills/seed-gates/SKILL.md"'
ok "end-phase: scoped to the phase marker glob"           'grep -q "tale-mode.phase.\*.json" "$PLUG/skills/end-phase/SKILL.md"'
ok "end-phase: leaves the ad-hoc goal-file alone"         'grep -q "active-goal" "$PLUG/skills/end-phase/SKILL.md"'

echo "4) pending-marker contract: skill instruction and Stop-hook adoption name the SAME file"
PENDNAME="tale-mode.phase.pending.json"
ok "stop-goal-loop.sh adopts $PENDNAME"                   'grep -q "$PENDNAME" "$PLUG/hooks/stop-goal-loop.sh"'
ok "kickoff-phase skill writes $PENDNAME"                 'grep -q "$PENDNAME" "$PLUG/skills/kickoff-phase/SKILL.md"'
ok "end-phase skill clears $PENDNAME too"                 'grep -q "$PENDNAME" "$PLUG/skills/end-phase/SKILL.md"'
ok "exactly one pending filename in the hook (no variant drift)" \
   '[ "$(grep -o "tale-mode\.phase\.[a-z]*\.json" "$PLUG/hooks/stop-goal-loop.sh" | sort -u | wc -l | tr -d " ")" = "1" ]'

echo "5) output style frontmatter is well-formed (validate does not parse it)"
OS="$PLUG/output-styles/tale-mode.md"
ok "output style: opens with ---"        '[ "$(head -n1 "$OS")" = "---" ]'
ok "output style: has a name"            'grep -qE "^name:" "$OS"'
ok "output style: has a description"     'grep -qE "^description:" "$OS"'

echo "6) command<->skill twin drift-guard: load-bearing phrases exist in BOTH twins"
# The commands (CC) and their skill twins (cross-platform) are edited by hand with a "keep in
# sync" comment. Full prose equality would be brittle (they deliberately differ per host), so we
# pin the LOAD-BEARING shared discipline phrases instead: if one twin drops or rewords one of
# these, the pair has genuinely diverged and this fires. Case-insensitive to tolerate emphasis.
_twin() { # $1 pair-name  $2 file-a  $3 file-b  $4 phrase   (globals: ok() evals in ITS scope,
  TA="$2"; TB="$3"; TP="$4"                                 # so $2/$3/$4 would rebind — see #9's eval)
  # Match against a whitespace-FLATTENED view of each file: prose reflows across lines (a phrase
  # wrapped mid-way is not drift), so line-based grep would false-positive on wrap. -F = literal.
  ok "$1: '$4' in both twins" \
     '{ tr "\n" " " < "$TA" | tr -s " " | grep -qiF -- "$TP"; } && { tr "\n" " " < "$TB" | tr -s " " | grep -qiF -- "$TP"; }'
}
KC="$PLUG/commands/kickoff-phase.md"; KS="$PLUG/skills/kickoff-phase/SKILL.md"
for p in "interview SHARP" "the code is ground truth; the plan is a snapshot" \
         "DECIDE and proceed" "recommend changing the plan" "owner-triggered" "push-loop" \
         "DONE/MISSING table" "re-review the post-fix delta" "named, owned deferral" \
         "prove it by running it, not by reading the diff"; do
  _twin "kickoff" "$KC" "$KS" "$p"
done
PC="$PLUG/commands/plan-phase.md"; PS="$PLUG/skills/plan-phase/SKILL.md"
for p in "Decisions with receipts" "my judgment — rationale" \
         "Never inscribe a constraint nobody gave you" "recommend changing the plan" \
         "Adversarial review — fresh eyes, looped" "independently-shippable phases" \
         "Engineering alternative" "Rollback + out-of-scope + known-untestable"; do
  _twin "plan" "$PC" "$PS" "$p"
done

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
