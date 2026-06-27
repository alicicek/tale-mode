#!/usr/bin/env bash
# tale-mode — SessionStart discipline injection (always-on, additive).
#
# WHAT IT DOES
#   Claude Code runs this on every SessionStart (source: startup | resume | clear |
#   compact). It prints a short, fixed reminder of tale-mode's core working
#   disciplines to stdout, and Claude Code adds a SessionStart hook's stdout to the
#   model's context. So the disciplines are present in EVERY session and survive
#   compaction — with nothing for the agent to remember or arm.
#
#   Purely ADDITIVE: it injects static text and overrides nothing (it is not an
#   output style and does not change the user's configured mode). Distilled from the
#   `tale-mode` skill (skills/tale-mode/SKILL.md, the canonical source); keep this in
#   sync when those disciplines change.
#
# SAFETY
#   Static text only. Reads no repo files, executes no project input, makes no
#   network calls, and needs no parser or non-standard tooling (only `cat`). It
#   always exits 0, so it can never block or fail a session start.
set -uo pipefail

# Drain and ignore stdin: Claude Code pipes the hook a JSON payload we don't need
# (the injected text is identical for every source); reading it keeps the writer
# from seeing a broken pipe.
cat >/dev/null 2>&1 || true

cat <<'EOF'
tale-mode — keep these core working disciplines live this session (the full method is in the `tale-mode` skill; right-size it, so trivial work still stays fast):

- Verify against ground truth, not memory. Before you rely on a file path, line number, API, or contract, re-read the actual source or run the actual command — don't trust your own earlier summary or memory of it, and remember a clean diff is not evidence it works. Cite what you checked (file:line, command output).
- Foundation-first when something breaks. Before asking *why* it's broken, confirm the thing EXISTS and the environment is CAPABLE of it — one existence/capability check often collapses the whole search.
- Two-strike rule. If two fixes in a row fail, STOP and re-verify the foundational assumption instead of trying a third — that's the alarm that you're debugging downstream of a false belief.
EOF

exit 0
