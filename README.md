# Tale Mode

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Claude Code skill](https://img.shields.io/badge/Claude%20Code-skill-d97757.svg)](https://docs.claude.com/en/docs/claude-code/skills)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](#contributing)

**Anthropic pulled the plug on Fable. Tale Mode was made by Fable to get Opus to act like Fable.**

Not smarter — *more disciplined.* A drop-in
[skill](https://docs.claude.com/en/docs/claude-code/skills) that makes any Claude
work like a careful senior engineer: verify the real code (never memory), receipts
on every decision, an *independent* adversarial review before it says "done," and
durable notes — right-sized, so a typo fix stays a typo fix. The model got pulled;
the method didn't.

**Contents:** [Quick start](#quick-start) · [Problem](#the-problem-it-targets) · [How it works](#how-it-works) · [Examples](#examples) · [Use it](#use-it) · [Autonomous loop](#autonomous-loop) · [What's different](#what-makes-it-different) · [Install](#install) · [Security & trust](#security--trust) · [Tuning](#tuning--effort--orchestration) · [Does it work?](#does-it-actually-work) · [What's in the box](#whats-in-the-box) · [Contributing](#contributing)

---

## Quick start

```bash
git clone https://github.com/alicicek/tale-mode && cd tale-mode && ./install.sh
```

Start a **new** Claude Code session (so it loads), then just ask:

> **tale mode** — refactor the auth middleware and prove it still blocks expired tokens

That's it. It picks how much process the task deserves, plans, verifies against the
real code, and tells you what it couldn't check. For bigger work, reach for the
[`/plan-phase` → `/kickoff-phase` pipeline](#use-it). No Claude Code? See
[other hosts](#install).

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

## How it works

A **right-size throttle** decides how much process a task earns (and, for big work,
how many phases to split it into) — so trivial work stays fast. Above that floor it
runs an 8-step loop:

| # | Step | What it forces |
|---|------|----------------|
| 1 | **Map** | Stage the work + define "done" before acting |
| 2 | **Receipts** | Every decision quotes a source or is labeled judgment |
| 3 | **Delegate** | Independent strands to parallel sub-agents (*don't* split coherent thought) |
| 4 | **Verify twice** | Internal consistency **and** against ground truth — a clean diff isn't evidence |
| 5 | **Critique** | Always self-critique; for high-stakes, a **separate** adversarial reviewer |
| 6 | **Ask** | Surface genuine forks instead of guessing |
| 7 | **Persist** | Progress to a durable file — the conversation isn't memory |
| 8 | **Surface gaps** | Name what's untested / out of scope |

The three tiers the throttle picks from:

- 🟢 **Trivial** — a typo, a rename, a one-liner: just do it. No ceremony.
- 🟡 **Substantial** — multi-file but reversible, no auth/money/data: the light loop.
- 🔴 **High-stakes** — auth / money / data / security, or hard to undo: the full loop,
  including the independent reviewer and durable notes.

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

## Use it

**Triggers:** **"tale mode"**, **"tale on"**, **"go deep"** — or it
self-activates on complex multi-step work.

**Slash commands** (Claude Code):

- `/plan-phase <task>` — plan to the full bar (verify-against-code, receipts,
  independent review, runnable gates) before any code. Large features come back
  **decomposed into independently-shippable phases**, each sized for one session.
- `/kickoff-phase <plan-file> <phase>` — implement **one** phase of a larger plan in
  a fresh session. **Runs under plan mode**: re-verifies the plan against the
  current code, interviews you, and waits for your approval before writing anything.

### The pipeline — one phase per session

Big features are built one phase at a time, each in its own session, so the working
context stays lean (a long session re-reads its whole window every turn):

```text
/plan-phase <big feature>        → phased plan on disk (Phase 1..N), approved
   /clear  → fresh session
/kickoff-phase plan.md "Phase 1" → plan mode → you approve → build → PR → stop
   /clear  → fresh session
/kickoff-phase plan.md "Phase 2" → …
```

The plan file on disk is the durable hand-off between sessions; `/clear` between
phases keeps each one fast. For a small, single-session task, skip the pipeline and
just use `/plan-phase` (or a trigger).

**Optional deterministic gates** (run typecheck/lint automatically after edits, so
"green before you continue" is enforced by the harness, not the model's memory):
see [`claude-code/HOOKS.md`](claude-code/HOOKS.md).

## Autonomous loop

Claude Code's `/goal` and `/loop` are user-only — *you* type them. Tale Mode adds a
loop the **agent starts itself**: it writes a goal-file (a success condition + a
*deterministic* `check` command), and a `Stop` hook refuses to let the turn end until
that check passes — so it grinds a real task to green without you re-prompting each
step. Opt-in — register the hooks from
[`claude-code/settings.example.jsonc`](claude-code/settings.example.jsonc).

```jsonc
// .claude/active-goal.json — the agent writes this at the start of a hard, verifiable task
{ "goal": "the auth E2E prints PASSED",
  "check": "npm test -- auth | grep -q PASSED",
  "rounds": 0, "max_rounds": 25, "needs_user": null }
```

- **Layer 1 — the loop** ([`hooks/stop-goal-loop.sh`](claude-code/hooks/stop-goal-loop.sh)):
  check fails → the turn is blocked with the *foundation-first / two-strike* disciplines
  injected; check passes → the goal clears. It can't run forever (`max_rounds` + a
  fail-open if it can't persist state), and it **pauses for you** (`needs_user`) when it
  hits something only you can do — a secret, a deploy, a go/no-go — instead of grinding
  the impossible. 31 tests cover the fail/pass/pause/edge paths.
- **Layer 2 — the governor** (optional, experimental): a **read-only** `type:"agent"`
  Stop hook that, once the agent is *stuck* (≥ 2 rounds), reads the plan/code with a fresh
  adversarial frame and names the unverified foundation, a violated documented constraint,
  or a band-aid — the failures the deterministic gate can't see.

**Honest scope.** This buys *autonomy*, not IQ. Verified live (`claude -p`): the
block→re-turn loop, multi-round iteration, `max_rounds` give-up, the agent self-arming a
goal, and the `needs_user` pause all work. But capable models already self-regulate —
they foundation-check and bail correctly — so the loop is mostly a **safety net** for the
rare real stall, not a daily multiplier. It's a seatbelt: proven to function, worth
wearing, most valuable on the bad day. Design rationale + the honest build log (including
the bugs an adversarial pass caught in this very hook):
[`docs/autonomous-loop-design.md`](docs/autonomous-loop-design.md).

## What makes it different

Beyond the general bones (stage map → delegate → verify → self-critique, domain
patterns, triggers), Tale Mode adds the three disciplines that separate "looks
right" from **is right**:

1. **Receipts / provenance** — decisions trace to a source; nothing laundered in.
2. **Independent adversarial review** — a *separate* agent that reads ground truth
   and tries to break the work, not just same-context self-critique (which can't
   see its own blind spot). *(Needs a sub-agent-capable host like Claude Code; on
   the claude.ai app it falls back to fresh-frame self-review — see
   [Install](#install).)*
3. **Verify against ground truth** — re-read the actual file / run the actual
   command, not "does my output match my plan" (internal consistency ≠ correctness).

Plus a **right-size throttle** so it doesn't ceremony-ize trivial tasks, and
**ask-on-genuine-forks** instead of guessing.

## Install

### Claude Code (recommended) — one command

```bash
git clone https://github.com/alicicek/tale-mode && cd tale-mode && ./install.sh
```

`./install.sh` installs for **all** projects (`~/.claude`); `./install.sh --project`
installs into the **current** repo's `.claude/`. It copies the skill, the
`plan-reviewer` agent, and the `/plan-phase` + `/kickoff-phase` commands, creating
directories as needed. Safe to re-run — an existing file that differs is backed up
to `<file>.bak` first. **Start a new Claude Code session afterward** so it loads.

New to running a stranger's skill? It's deliberately tiny and readable — see
[Security & trust](#security--trust) before you run anything.

**Or just hand your agent the link:**

> Install Tale Mode from https://github.com/alicicek/tale-mode — clone it and run
> `./install.sh` for user scope, then tell me how to trigger it.

<details><summary><b>Manual install</b> (what the script does)</summary>

```bash
mkdir -p ~/.claude/skills/tale-mode ~/.claude/agents ~/.claude/commands
cp SKILL.md                              ~/.claude/skills/tale-mode/SKILL.md
cp claude-code/agents/plan-reviewer.md   ~/.claude/agents/plan-reviewer.md
cp claude-code/commands/*.md             ~/.claude/commands/
```

(swap `~/.claude` → `.claude` for a single project)

</details>

**claude.ai app:** put `SKILL.md` in a folder named `tale-mode`, zip the folder,
and upload at `claude.ai/customize/skills`.

> **Platform support.** The full skill — including the parallel-delegation step
> and the *independent* adversarial review — needs a host that can spawn
> sub-agents (Claude Code, today). On the claude.ai app those two steps degrade
> gracefully: run the strands sequentially and do the review as a deliberately
> hostile, fresh-frame self-review. The other six steps apply identically
> everywhere.

## Security & trust

A skill is loaded into your agent's context and, in Claude Code, runs with the
same privileges you have — so "only install skills you trust" is the right
instinct (it's [Anthropic's own advice](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)).
The honest answer to "is this safe?" isn't *trust me* — it's *read it, it's tiny.*
The whole project is plain Markdown plus a short install script and one small Stop-hook
shell script; the entire attack surface is a handful of files you can skim in a few minutes.

**What it does / doesn't do**

- **No telemetry, no analytics, no background network calls.** `SKILL.md`, the
  slash-command files, and `install.sh` send nothing anywhere. `install.sh` only
  runs `mkdir`/`cp`/`cmp` to copy files into your `~/.claude` (or `./.claude`).
- **Two capabilities worth flagging:** (1) the bundled `plan-reviewer` subagent is
  granted `Bash` + `WebFetch` (see
  [`claude-code/agents/plan-reviewer.md`](claude-code/agents/plan-reviewer.md)) so it can
  run your project's checks and verify cited sources — **only when you invoke a review**,
  under Claude Code's normal permission prompts. (2) the **opt-in** autonomous-loop hook
  ([`claude-code/hooks/stop-goal-loop.sh`](claude-code/hooks/stop-goal-loop.sh)) is a Stop
  hook: once *you've registered it* and the agent has armed a goal-file, it runs that
  goal-file's `check` command when the turn would otherwise end (unless the goal is paused
  for you or has hit its round cap). It does nothing unless you register it **and** a goal-file
  exists; the `check` is a command the agent wrote in your repo — read the script
  (~110 lines) before enabling.
- It never asks Claude to read secrets, weaken security, or run destructive
  commands. The whole point is to make Claude *more* careful.

**Verify before you run** — read these files; that's everything:
`SKILL.md` · `install.sh` · `claude-code/agents/plan-reviewer.md` ·
`claude-code/commands/plan-phase.md` · `claude-code/commands/kickoff-phase.md`. And before
you enable the optional loop: `claude-code/hooks/stop-goal-loop.sh` + `settings.example.jsonc`.

**Pin it** (recommended for shared or work machines) — review a commit, then
install exactly that version instead of tracking `main`:

```bash
git clone https://github.com/alicicek/tale-mode && cd tale-mode
git checkout <commit-sha>   # a commit you've read — copy the SHA from GitHub
less install.sh             # confirm: it only copies files into ~/.claude
./install.sh
```

Found a problem? See [`SECURITY.md`](SECURITY.md).

## Tuning — effort & orchestration

Two independent dials, once it's running:

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

## What's in the box

```text
tale-mode/
├── README.md, LICENSE, SECURITY.md   # readme · MIT license · disclosure policy
├── SKILL.md                 # the operating mode (portable — works on any host)
├── install.sh               # one-command installer (user or --project scope)
├── docs/
│   └── autonomous-loop-design.md   # design rationale + honest build log
└── claude-code/             # Claude Code-specific assets
    ├── HOOKS.md             # optional deterministic typecheck/lint gates
    ├── settings.example.jsonc      # register the autonomous-loop hooks (opt-in)
    ├── hooks/
    │   ├── stop-goal-loop.sh        # the self-armed goal loop (Layer 1)
    │   └── test-stop-goal-loop.sh   # 31 tests for its fail/pass/edge paths
    ├── agents/
    │   └── plan-reviewer.md  # the independent adversarial reviewer
    └── commands/
        ├── plan-phase.md     # /plan-phase  — verified, phased planning
        └── kickoff-phase.md  # /kickoff-phase — build one phase, under plan mode
```

`SKILL.md` is the whole methodology and is the only file the claude.ai app needs.
Everything under `claude-code/` adds the sub-agent and slash-command machinery that
hosts with delegation can use.

## Contributing

Issues and PRs welcome. This repo is dogfooded — if you're proposing a change to
the methodology, run it through the `plan-reviewer` agent first and include what it
found (that's the [receipts](#what-makes-it-different) discipline applied to
the repo itself). Keep edits to `SKILL.md` host-agnostic; put anything
Claude Code-specific under `claude-code/`.

## License

MIT licensed — see [`LICENSE`](LICENSE).
