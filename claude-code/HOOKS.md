# Deterministic gates via hooks (optional · Claude Code)

Hooks run shell commands automatically, so "green before you continue" is enforced
by the harness instead of relying on the model to remember. This complements
Tale Mode §4 (verify against ground truth) — the model still reasons, but a
typecheck/lint failure is now a hard stop.

Add a `PostToolUse` hook to `.claude/settings.json` that runs your project's real
check after edits and exits non-zero on failure (a non-zero exit is surfaced back
to Claude to fix before moving on):

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "npm run -s typecheck || exit 2" }
        ]
      }
    ]
  }
}
```

Notes:

- Swap the command for whatever your project uses — `tsc --noEmit`, `npm run lint`,
  `node --check <file>`, `ruff check`, etc.
- The hook receives the tool-call payload (including the edited file path) as JSON
  on **stdin** — parse it with `jq` if you want to gate only the changed file
  rather than the whole repo. Check the Claude Code hooks docs for the exact
  payload shape in your version before relying on a specific field.
- Keep hooks **fast** — they run on every matching edit. Gate narrowly; save the
  full test suite for the verification step, not the hook.
