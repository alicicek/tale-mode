#!/usr/bin/env bash
# Tale Mode installer for Claude Code.
#
#   ./install.sh            install for ALL projects   (~/.claude)
#   ./install.sh --project  install into THIS project  (./.claude)
#
# Copies the skill, the plan-reviewer agent, and the /plan-phase + /kickoff-phase
# commands, creating directories as needed. Safe to re-run: an existing file that
# differs is backed up to <file>.bak before being overwritten.
set -euo pipefail

SCOPE="user"
[ "${1:-}" = "--project" ] && SCOPE="project"

if [ "$SCOPE" = "project" ]; then BASE="$PWD/.claude"; else BASE="$HOME/.claude"; fi
SRC="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$BASE/skills/tale-mode" "$BASE/agents" "$BASE/commands"

# Copy src -> dest, backing up an existing, differing dest to dest.bak first.
install_file() {
  local src="$1" dest="$2"
  if [ -e "$dest" ] && ! cmp -s "$src" "$dest"; then
    cp "$dest" "$dest.bak"
    echo "  ↩ backed up existing ${dest} → ${dest}.bak"
  fi
  cp "$src" "$dest"
}

install_file "$SRC/SKILL.md"                            "$BASE/skills/tale-mode/SKILL.md"
install_file "$SRC/claude-code/agents/plan-reviewer.md" "$BASE/agents/plan-reviewer.md"
for f in "$SRC/claude-code/commands/"*.md; do
  install_file "$f" "$BASE/commands/$(basename "$f")"
done

echo "✓ Tale Mode installed (scope: $SCOPE) → $BASE"
echo "    skill:    skills/tale-mode/SKILL.md"
echo "    agent:    agents/plan-reviewer.md"
echo "    commands: commands/plan-phase.md, commands/kickoff-phase.md"
echo
echo "Start a new Claude Code session so it loads them, then trigger with:"
echo "  \"tale mode\"  ·  \"tale on\"  ·  \"go deep\""
echo "or run  /plan-phase <task>  ·  /kickoff-phase <plan-file> <chunk>"
