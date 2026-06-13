# Tale Mode

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Make Claude work like a careful senior engineer, not an eager intern.**

A drop-in operating mode (a [skill](https://docs.claude.com/en/docs/claude-code/skills))
that enforces the disciplines strong models skip when they rush: plan before
acting, back every decision with a source, **verify claims against the real files
(not memory)**, get an *independent* review on risky work, and keep durable notes.


> **Honest scope:** this does **not** make the model smarter or close any
> raw-capability gap. It changes *how* it works — trading a little speed for
> correctness you can trust.

**Contents:** [Problem](#the-problem-it-targets) · [What's inside](#whats-inside) · [Examples](#examples) · [What's different](#what-makes-it-different) · [Install](#install) · [Use it](#use-it) · [Effort & orchestration](#how-to-operate-it-well--effort--orchestration) · [Does it work?](#does-it-actually-work)

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

A **right-size throttle** (trivial work stays fast) plus an 8-step loop for
substantial / high-stakes work:

1. **Map** the stages + define "done" before acting
2. **Receipts** — every decision quotes a source or is labeled judgment
3. **Delegate** independent strands to parallel sub-agents (and *don't* split coherent thought)
4. **Verify twice** — internal consistency *and* against ground truth (a clean diff isn't evidence)
5. **Critique** — always self-critique (name the most consequential weakness); for high-stakes, a **separate** adversarial reviewer agent
6. **Ask** on genuine forks instead of guessing
7. **Persist** progress to a durable file (the conversation isn't memory)
8. **Surface gaps** — name what's untested / out of scope

## Examples

Same trigger, different amount of process — Tale Mode right-sizes to the task.

**🟢 Trivial — it stays out of your way**

> tale mode — fix the typo in the pricing heading

Recognizes it's trivial and just does it: no staged plan, no sub-agents, no
review. (Ceremony on a one-liner is its own failure mode.)

**🟡 Substantial — the light loop** *(multi-file, reversible, no auth/money/data)*

> tale mode — migrate the marketing pages to the new framework

Maps the work, **verifies its claims against the real files** (re-reads them
instead of trusting memory), self-critiques, and flags anything it couldn't
check. Skips the heavyweight reviewer.

**🔴 High-stakes — the full loop** *(auth / money / data / security, or hard to undo)*

> tale mode — implement Phase 2 of PLAN.md, only that phase

Re-verifies the plan against the actual code, **interviews you** on genuine forks,
works on a dedicated branch, **proves it by running it** — and for cross-browser
UI, checks a real **WebKit/Safari** render, not just Chromium — then runs an
**independent reviewer** before you ship, and updates the plan file when done.

**🔴 Where the independent reviewer earns its keep — money / security**

> tale mode — change how the payment webhook verifies signatures

Because it touches money, it spawns a **separate** reviewer that reads the payment
code independently and hunts the traps self-review misses — e.g. consuming the
request body before verifying the signature, or an idempotency/race hole —
*before* the change ships.

**🔍 Debugging — don't trust the happy path**

> tale mode — users say the page looks broken on iPhone; find out why

Reproduces against ground truth — a real Safari/WebKit render, not just Chromium
devtools — reads the actually-served files, and won't call it "fixed" off a clean
diff. (The discipline that catches cross-browser bugs in one pass instead of five.)

**🛠 Slash commands**

> /plan-phase add rate-limiting to the public API

A verified, receipts-backed, independently-reviewed plan you approve before any
code is written.

> /kickoff-phase PLAN.md 3

Starts one scoped chunk of a larger plan in a fresh session: interviews you first,
then builds only that chunk.

## What makes it different

Beyond the general bones (stage map → delegate → verify → self-critique, domain
patterns, triggers), Tale Mode adds the three disciplines that separate "looks
right" from **is right**:

1. **Receipts / provenance** — decisions trace to a source; nothing laundered in.
2. **Independent adversarial review** — a *separate* agent that reads ground truth
   and tries to break the work, not just same-context self-critique (which can't
   see its own blind spot). *(Needs a sub-agent-capable host like Claude Code; on
   the claude.ai app it falls back to fresh-frame self-review — see [Platform
   support](#install).)*
3. **Verify against ground truth** — re-read the actual file / run the actual
   command, not "does my output match my plan" (internal consistency ≠ correctness).

Plus a **right-size throttle** so it doesn't ceremony-ize trivial tasks, and
**ask-on-genuine-forks** instead of guessing.

## Install

### Claude Code — one command

```
git clone https://github.com/alicicek/tale-mode && cd tale-mode && ./install.sh
```

`./install.sh` installs for **all** projects (`~/.claude`); `./install.sh --project`
installs into the **current** repo's `.claude/`. It copies the skill, the
`plan-reviewer` agent, and the `/plan-phase` + `/kickoff-phase` commands, creating
the directories as needed (safe to re-run). **Start a new Claude Code session
afterward** so it loads them.

**Or just tell your agent** (hand it the link):

> Install Tale Mode from https://github.com/alicicek/tale-mode — clone it and run
> `./install.sh` for user scope, then tell me how to trigger it.

<details><summary>Manual install (what the script does)</summary>

```
mkdir -p ~/.claude/skills/tale-mode ~/.claude/agents ~/.claude/commands
cp SKILL.md                              ~/.claude/skills/tale-mode/SKILL.md
cp claude-code/agents/plan-reviewer.md   ~/.claude/agents/plan-reviewer.md
cp claude-code/commands/*.md             ~/.claude/commands/
```
(swap `~/.claude` → `.claude` for a single project)
</details>

**claude.ai app:** put `SKILL.md` in a folder named `tale-mode`, zip the folder,
upload at `claude.ai/customize/skills`.

> **Platform support.** The full skill — including the parallel-delegation step
> and the *independent* adversarial review — needs a host that can spawn
> sub-agents (Claude Code, today). On the claude.ai app those two steps degrade
> gracefully: run the strands sequentially and do the review as a deliberately
> hostile, fresh-frame self-review. The other six steps apply identically
> everywhere.

## Use it

**Triggers:** **"tale mode"**, **"deep work mode"**, **"do this properly"** — or it
self-activates on complex multi-step work.

**Slash commands** (Claude Code — see [Examples](#examples)):
- `/plan-phase <task>` — plan to the full bar (verify-against-code, receipts,
  independent review, runnable gates) before any code.
- `/kickoff-phase <plan-file> <chunk>` — start one scoped chunk of a larger plan
  in a fresh session; interviews you first, then builds only that chunk.

Optional deterministic gates (typecheck/lint after edits): see
[`claude-code/HOOKS.md`](claude-code/HOOKS.md).

## How to operate it well — effort & orchestration

These are different dials:

- **Effort = reasoning depth.** Default **xhigh** for planning, review, and
  execution — deep but responsive. Use **max** only for the single hardest
  reasoning passes (a thorny architecture call; reviewing a money/security
  change); it's slower with diminishing returns and can over-deliberate, so it's a
  poor everyday default *even on an unlimited plan*.
- **Multi-agent orchestration** (e.g. Claude Code's "ultracode"). Turn it on for
  big, multi-step, high-stakes work (migrations, audits, comprehensive plans) — it
  fans out agents and adversarially verifies. Overkill for small tasks; the
  right-size throttle keeps it from over-firing.
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
are in the commit history. (A receipt — the discipline the skill itself demands —
instead of a "trust me.")

## Credits & license

MIT licensed — see [`LICENSE`](LICENSE).
