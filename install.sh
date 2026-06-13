#!/usr/bin/env bash
# Tale Mode installer for Claude Code.
#
#   ./install.sh            install for ALL projects   (~/.claude)
#   ./install.sh --project  install into THIS project  (./.claude)
#
# Copies the skill, the plan-reviewer agent, and the /plan-phase + /kickoff-phase
# commands, creating directories as needed. Safe to re-run (overwrites in place).
set -euo pipefail

SCOPE="user"
[ "${1:-}" = "--project" ] && SCOPE="project"

if [ "$SCOPE" = "project" ]; then BASE="$PWD/.claude"; else BASE="$HOME/.claude"; fi
SRC="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$BASE/skills/tale-mode" "$BASE/agents" "$BASE/commands"
cp "$SRC/SKILL.md"                              "$BASE/skills/tale-mode/SKILL.md"
cp "$SRC/claude-code/agents/plan-reviewer.md"   "$BASE/agents/plan-reviewer.md"
cp "$SRC/claude-code/commands/"*.md             "$BASE/commands/"

echo "✓ Tale Mode installed (scope: $SCOPE) → $BASE"
echo "    skill:    skills/tale-mode/SKILL.md"
echo "    agent:    agents/plan-reviewer.md"
echo "    commands: commands/plan-phase.md, commands/kickoff-phase.md"
echo
echo "Start a new Claude Code session so it loads them, then trigger with:"
echo "  \"tale mode\"  ·  \"deep work mode\"  ·  \"do this properly\""
echo "or run  /plan-phase <task>  ·  /kickoff-phase <plan-file> <chunk>"
