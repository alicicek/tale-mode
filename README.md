# Tale Mode

A drop-in operating mode that makes Claude do the rigorous work it tends to skip
when it's moving fast: plan in explicit stages, back every decision with a source,
**verify claims against the actual code/files (not its own memory)**, delegate
independent work in parallel, run an *independent* adversarial review on
high-stakes output, and keep durable progress notes.

> **Honest scope.** This does **not** make the model smarter or close any
> raw-capability gap. It changes *how* the model works — trading a little speed
> for correctness you can trust. Inspired by
> See [What's different](#what-makes-it-different).

## The problem it targets

Strong models, under time pressure, predictably cut the same corners:

- act before understanding; one-shot a multi-step task
- trust their own summary of a file instead of re-reading it (stale claims, wrong
  line numbers, invented APIs)
- agree too readily and inscribe constraints nobody asked for
- review their own work — and miss the framing error they're *inside*
- drift on long tasks; forget earlier decisions
- declare "done" from the diff without running anything
- either over-engineer trivia or take shortcuts on the hard part

Tale Mode is a checklist-as-skill that targets each of these.

## What's inside

A **right-size throttle** (trivial work stays fast) plus an 8-part loop for
substantial / high-stakes work:

1. **Map** the stages + define "done" before acting
2. **Receipts** — every decision quotes a source or is labeled judgment
3. **Delegate** independent strands to parallel sub-agents (and *don't* split coherent thought)
4. **Verify twice** — internal consistency *and* against ground truth (a clean diff isn't evidence)
5. **Critique** — always self-critique (name ≥1 weakness); for high-stakes, a **separate** adversarial reviewer agent
6. **Ask** on genuine forks instead of guessing
7. **Persist** progress to a durable file (the conversation isn't memory)
8. **Surface gaps** — name what's untested / out of scope

## What makes it different

Beyond the general bones (stage map → delegate → verify → self-critique, domain patterns, triggers), Tale Mode adds the three disciplines that separate "looks
right" from **is right**:

1. **Receipts / provenance** — decisions trace to a source; nothing laundered in.
2. **Independent adversarial review** — a *separate* agent that reads ground truth
   and tries to break the work, not just same-context self-critique (which can't
   see its own blind spot). *(Needs a sub-agent-capable host like Claude Code; on
   the claude.ai app it falls back to fresh-frame self-review — see Platform
   support below.)*
3. **Verify against ground truth** — re-read the actual file / run the actual
   command, not "does my output match my plan" (internal consistency ≠ correctness).

Plus a **right-size throttle** so it doesn't ceremony-ize trivial tasks, and
**ask-on-genuine-forks** instead of guessing.

## Install

**Claude Code** (project scope — swap `.claude/` → `~/.claude/` for all projects):

```
cp SKILL.md                          .claude/skills/tale-mode/SKILL.md
cp claude-code/agents/plan-reviewer.md   .claude/agents/plan-reviewer.md
cp claude-code/commands/*.md             .claude/commands/
```

**claude.ai app:** put `SKILL.md` in a folder named `tale-mode`, zip the
folder, upload at `claude.ai/customize/skills`.

> **Platform support.** The full skill — including parallel delegation (§3) and
> the *independent* adversarial review (§5) — needs a host that can spawn
> sub-agents (Claude Code, today). On the claude.ai app those two steps degrade
> gracefully: run the strands sequentially and do §5 as a deliberately hostile,
> fresh-frame self-review. The other six steps apply identically everywhere.

## Use it

Triggers: **"tale mode"**, **"be systematic"**, **"deep work mode"**, **"do this properly"** — or it
self-activates on complex multi-step work. In Claude Code:

- `/plan-phase <task>` — plan a task to the full bar (verify-against-code,
  receipts, adversarial review, runnable gates).
- `/kickoff-phase <plan-file> <chunk>` — start a scoped chunk of a larger plan in
  a fresh session; it **interviews you first**, then implements only that chunk.

Optional deterministic gates (typecheck/lint after edits): see
[`claude-code/HOOKS.md`](claude-code/HOOKS.md).

## How to operate it well — effort & orchestration

These are different dials:

- **Effort = reasoning depth.** Default **xhigh** for planning, review, and
  execution — deep but responsive. Use **max** only for the single hardest
  reasoning passes (a thorny architecture call; reviewing a money/security
  change); it's slower with diminishing returns and can over-deliberate, so it's a
  poor everyday default *even on an unlimited plan*.
- **Multi-agent orchestration (e.g. "ultracode").** Turn it on for big,
  multi-step, high-stakes work (migrations, audits, comprehensive plans) — it fans
  out agents and adversarially verifies. Overkill for small tasks; the §0 throttle
  keeps it from over-firing.
- **On an unlimited plan:** optimize for correctness + your own latency tolerance,
  not cost. Lean toward xhigh + orchestration-on-big-things — but don't
  cargo-cult max-everything.

## Does it actually work?

Honestly: a skill that asserts "the model now plans and self-critiques" will
trivially pass an eval that *checks for planning and self-critique* — the
un-skilled baseline "fails" assertions it was never asked to satisfy. A
100%-vs-0% number like that is **circular**; treat it (and any you see quoted for
tools like this) with skepticism. The real test is **output quality on hard
tasks**.

To judge it yourself: run the same genuinely-hard task twice (with and without the
mode), then have a *fresh* session adversarially review both outputs against the
source. Look for fewer stale claims, sourced decisions, and caught traps — not for
the model "sounding more thorough."

This repo was built with its own method: `SKILL.md` was run through the
`plan-reviewer` agent it ships, and the findings — plus the fixes they produced —
are in the commit history. (A receipt, per §2, instead of a "trust me.")

## Credits & license

MIT licensed — see [`LICENSE`](LICENSE).
