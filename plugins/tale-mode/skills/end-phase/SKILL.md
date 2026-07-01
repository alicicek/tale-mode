---
name: end-phase
description: >-
  Explicitly end a tale-mode build phase by clearing the phase marker(s) under
  <project>/.claude/, which stops the Stop-hook's committed-gate enforcement for this repo.
  Invoke ONLY when the user explicitly asks to end the phase, stop or disarm the tale-mode
  phase loop, or clean up phase markers — never proactively, and never as a way to escape a
  failing gate.
---

# End a phase

A `/tale-mode:kickoff-phase` (or the `kickoff-phase` skill) arms committed-gate enforcement by
writing a session-scoped marker `<project>/.claude/tale-mode.phase.<session-id>.json`. Normally you
never need this skill — the marker dies with the session (`/clear` orphans it and a ~24h reap
removes strays), and hitting `max_rounds` disarms it. This skill is the **explicit, immediate
off-switch**: the user has decided the phase is over (shipped, abandoned, or being re-scoped) and
wants enforcement gone *now*, mid-session.

**Guardrail first:** if a committed gate is currently RED and the user hasn't clearly said to stop
the phase, do NOT reach for this skill — driving the gate to green (or pausing via `needs_user` in
the marker) is the designed path. Ending a phase to silence a failing gate is the exact band-aid
tale-mode exists to prevent; confirm intent before clearing.

**To end the phase**, from the project root:

```bash
ls .claude/tale-mode.phase.*.json 2>/dev/null   # see what's armed (may be none)
rm -f .claude/tale-mode.phase.*.json            # clear it/them
```

Notes, so you report accurately:

- You can't know your own session id, so clear **all** markers matching the glob. That's safe:
  any non-current markers belong to crashed/old sessions (each session only ever reads its own),
  and a marker only *enables* enforcement of gates the user already content-hash-trusted — clearing
  markers just returns every session in this repo to normal, un-enforced behavior.
- This also removes a not-yet-adopted `.claude/tale-mode.phase.pending.json` (the cross-platform
  kickoff arming file), un-arming a kickoff that hasn't had its first Stop event yet.
- This does **not** touch an ad-hoc goal-file (`.claude/active-goal*.json`) — that's the separate
  agent-armed loop. Mention it if one exists; only delete it when the user asks for that too (and
  explain why, per the goal-loop's own rules).
- No markers found → say so; nothing was armed, nothing to end.
- Confirm the result to the user: what was removed, and that the committed gates are now inert
  until the next kickoff.
