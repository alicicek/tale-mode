# Tale Mode

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-d97757.svg)](https://docs.claude.com/en/docs/claude-code/plugins)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](#contributing)

**Anthropic pulled the plug on Fable. Tale Mode was made by Fable to get Opus to act like Fable.**

Not smarter — *more disciplined.* A drop-in Claude Code **plugin** that makes any Claude
work like a careful senior engineer: verify the real code (never memory), receipts on
every decision, an *independent* adversarial review before it says "done," durable notes —
and a **self-armed autonomous loop** that keeps going until a real check passes. Right-sized,
so a typo fix stays a typo fix. The model got pulled; the method didn't.

**Contents:** [Quick start](#quick-start) · [Problem](#the-problem-it-targets) · [How it works](#how-it-works) · [Examples](#examples) · [Use it](#use-it) · [Autonomous loop](#autonomous-loop) · [What's different](#what-makes-it-different) · [Install](#install) · [Security & trust](#security--trust) · [Tuning](#tuning--effort--orchestration) · [Does it work?](#does-it-actually-work) · [What's in the box](#whats-in-the-box) · [Managing / removing](#managing--removing) · [Contributing](#contributing)

---

## Quick start

```text
/plugin marketplace add alicicek/tale-mode
/plugin install tale-mode@tale-mode
```

Restart Claude Code (so it loads), then just ask:

> **tale mode** — refactor the auth middleware and prove it still blocks expired tokens

That's it. It picks how much process the task deserves, plans, verifies against the real
code, and tells you what it couldn't check. For bigger work, reach for the
[`/tale-mode:plan-phase` → `/tale-mode:kickoff-phase` pipeline](#use-it). Requires
Claude Code **≥ v2.1.154**.

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

**Three separate things turn it on — don't confuse them:**

- **The discipline (the skill)** — say **"tale mode"** or **"tale on"**, or it
  self-activates on complex multi-step work. This is the everyday mode: plan → verify →
  review → receipts. It's *soft* — the model loads the skill when the work matches.
- **The phase commands (explicit)** — `/tale-mode:plan-phase` and
  `/tale-mode:kickoff-phase`, for big multi-phase features (below). You type these.
- **The autonomous loop (the hooks)** — runs by itself; see [Autonomous loop](#autonomous-loop).
  You don't trigger it — the agent arms a goal-file and a `Stop` hook keeps it going.

**Slash commands** (namespaced under the plugin):

- `/tale-mode:plan-phase <task>` — plan to the full bar (verify-against-code, receipts,
  independent review, runnable gates) before any code. Large features come back
  **decomposed into independently-shippable phases**, each sized for one session.
- `/tale-mode:kickoff-phase <plan-file> <phase>` — implement **one** phase of a larger plan in
  a fresh session. **Runs under plan mode**: re-verifies the plan against the
  current code, interviews you, and waits for your approval before writing anything.

### The pipeline — one phase per session

Big features are built one phase at a time, each in its own session, so the working
context stays lean (a long session re-reads its whole window every turn):

```text
/tale-mode:plan-phase <big feature>          → phased plan on disk (Phase 1..N), approved
   /clear  → fresh session
/tale-mode:kickoff-phase plan.md "Phase 1"   → plan mode → you approve → build → PR → stop
   /clear  → fresh session
/tale-mode:kickoff-phase plan.md "Phase 2"   → …
```

The plan file on disk is the durable hand-off between sessions; `/clear` between
phases keeps each one fast. For a small, single-session task, skip the pipeline and
just use `/tale-mode:plan-phase` (or a trigger).

**Optional deterministic gates** (run typecheck/lint automatically after edits, so
"green before you continue" is enforced by the harness, not the model's memory):
see [`docs/HOOKS.md`](docs/HOOKS.md).

## Autonomous loop

Claude Code's `/goal` and `/loop` are user-only — *you* type them. Tale Mode ships a
loop the **agent starts itself**: it writes a goal-file (a success condition + a
*deterministic* `check` command), and a bundled `Stop` hook refuses to let the turn end
until that check passes — so it grinds a real task to green without you re-prompting each
step. **It's live the moment the plugin is installed** — the hook ships *inside* the
plugin; there's nothing to wire up.

```jsonc
// .claude/active-goal.json — the agent writes this at the start of a hard, verifiable task
{ "goal": "the auth E2E prints PASSED",
  "check": "npm test -- auth | grep -q PASSED",
  "rounds": 0, "max_rounds": 25, "needs_user": null }
```

- **Layer 1 — the loop** (`hooks/stop-goal-loop.sh`, free bash): check fails → the turn is
  blocked with the *foundation-first / two-strike* disciplines injected; check passes → the
  goal clears. It can't run forever (`max_rounds` + a fail-open if it can't persist state),
  and it **pauses for you** (`needs_user`) when it hits something only you can do — a secret,
  a deploy, a go/no-go — instead of grinding the impossible. **Silent (zero cost) until a
  goal is armed.** When armed, it appends one JSONL verdict line per round to a local
  `.claude/tale-mode.log` audit trail (disable with `TALE_VERDICT_LOG=/dev/null`).
  62 tests cover the fail/pass/pause/edge/log paths.
- **Layer 2 — the governor** (optional, *separate* plugin): a **read-only** `type:"agent"` Stop hook
  pinned to **Sonnet** that, once the agent is *stuck* (≥ 2 rounds), reads the plan/code with a fresh
  adversarial frame and names the unverified foundation, a violated documented constraint, or a
  band-aid — the failures the deterministic gate can't see. It ships as a **companion plugin** you add
  only if you want it: `/plugin install tale-mode-governor@tale-mode`.

  > **Why it's separate (honest):** an agent `Stop` hook makes a small **Sonnet call on every
  > turn-end** — even with no goal armed it spawns, finds no goal-file, and exits — so while it's
  > enabled it adds a little per-turn latency + token cost to *all* usage. L1 (the core) is a free
  > instant bash check, so the **default install stays free + snappy**; the governor is opt-in for
  > those who want anchor-breaking on stuck loops. Remove it any time with
  > `/plugin uninstall tale-mode-governor@tale-mode`.

**Longer loops.** Out of the box the loop stops after Claude Code's default **8 consecutive
blocked turns** (a platform backstop) even if `max_rounds` is higher — a plugin can't change
that env var. For loops that legitimately need more, raise it once in `~/.claude/settings.json`:

```json
{ "env": { "CLAUDE_CODE_STOP_HOOK_BLOCK_CAP": "30" } }
```

The loop is safe without this — `max_rounds` + the fail-open are self-contained; the cap is
just a belt.

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
   see its own blind spot).
3. **Verify against ground truth** — re-read the actual file / run the actual
   command, not "does my output match my plan" (internal consistency ≠ correctness).

Plus a **right-size throttle** so it doesn't ceremony-ize trivial tasks, and
**ask-on-genuine-forks** instead of guessing.

## Install

Two commands inside Claude Code:

```text
/plugin marketplace add alicicek/tale-mode
/plugin install tale-mode@tale-mode               # core: skill + commands + agent + the free loop
/plugin install tale-mode-governor@tale-mode      # OPTIONAL: the Sonnet governor (per-turn cost)
```

Then **restart Claude Code** (or run `/reload-plugins`). The **core** plugin is enabled on install
(`defaultEnabled`), so the skill, the `/tale-mode:plan-phase` + `/tale-mode:kickoff-phase` commands,
the `plan-reviewer` agent, and the free Layer-1 loop are live immediately. The **governor** is a
*separate, optional* install — it adds a per-turn model call (see [Autonomous loop](#autonomous-loop)).
Requires **Claude Code ≥ v2.1.154**.

**Verify it loaded:** `/skills` lists `tale-mode` · `/tale-mode:plan-phase` appears in the
`/` menu · `/agents` lists `tale-mode:plan-reviewer`.

**Not on Claude Code?** The *discipline itself* is portable — the skill at
[`plugins/tale-mode/skills/tale-mode/SKILL.md`](plugins/tale-mode/skills/tale-mode/SKILL.md)
works on the claude.ai app: put it in a folder named `tale-mode`, zip it, and upload at
`claude.ai/customize/skills`. The plugin machinery (commands, agent, autonomous loop) is
Claude-Code-only.

## Security & trust

A plugin loads into your agent's context and, in Claude Code, runs with the same
privileges you have — so "only install plugins you trust" is the right instinct (it's
[Anthropic's own advice](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)).
The honest answer to "is this safe?" isn't *trust me* — it's *read it, it's tiny.* The whole
plugin is plain Markdown, two small shell scripts (a Stop gate plus a tiny SessionStart injector), and small JSON manifests —
a handful of files you can skim in a few minutes.

**What it does / doesn't do**

- **No telemetry, no analytics, no background network calls.** The skill, command files,
  and the loop hook send nothing anywhere.
- **Install/uninstall is Claude Code's built-in `/plugin` mechanism.** It does **not**
  hand-edit your `~/.claude/settings.json` hooks or permissions — it only records the plugin
  in a Claude-Code-managed `enabledPlugins` registry. `/plugin uninstall tale-mode@tale-mode`
  removes everything (skill, commands, agent, hooks) cleanly, with no settings surgery.
- **Three capabilities worth flagging:**
  1. the bundled `plan-reviewer` agent is granted `Bash` + `WebFetch` so it can run your
     project's checks and verify cited sources — **only when you invoke a review**, under
     Claude Code's normal permission prompts.
  2. the **autonomous-loop Stop hook is on by default**. It runs on every turn-end but **does
     nothing until the agent arms a `.claude/active-goal.json`**; when armed, it runs *that
     goal-file's `check` command* — a shell command the agent wrote in your repo — to decide
     whether to keep going. Read
     [`plugins/tale-mode/hooks/stop-goal-loop.sh`](plugins/tale-mode/hooks/stop-goal-loop.sh)
     (~160 lines) so you know exactly what runs and when.
  3. the **Layer-2 governor** is a **read-only** (`Read`/`Grep`/`Glob`) Sonnet hook — it can
     read your code to spot an anchor, but cannot run shell or write files.
- It never asks Claude to read secrets, weaken security, or run destructive commands. The
  whole point is to make Claude *more* careful.

**Read these before you trust it** (all under `plugins/tale-mode/`):
`skills/tale-mode/SKILL.md` · `commands/plan-phase.md` · `commands/kickoff-phase.md` ·
`agents/plan-reviewer.md` · `hooks/stop-goal-loop.sh` · `hooks/session-start.sh` ·
`hooks/hooks.json` · `output-styles/tale-mode.md`.

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
tale-mode/                                 (repo — also the plugin marketplace)
├── .claude-plugin/
│   └── marketplace.json                   # makes the repo installable via /plugin
├── README.md · LICENSE · SECURITY.md
├── docs/                                  # rationale + notes (not shipped in the plugin)
│   ├── autonomous-loop-design.md          #   design rationale + honest build log
│   └── HOOKS.md                           #   optional deterministic typecheck/lint gates
├── tests/
│   ├── test-stop-goal-loop.sh             # tests for the Stop loop hook
│   └── test-session-start.sh              # tests for the SessionStart hook
└── plugins/
    ├── tale-mode/                         # CORE plugin (free)
    │   ├── .claude-plugin/plugin.json     # metadata (defaultEnabled)
    │   ├── skills/tale-mode/SKILL.md      # the discipline (auto-activates on "tale mode")
    │   ├── commands/                      # /tale-mode:plan-phase · /tale-mode:kickoff-phase
    │   ├── agents/plan-reviewer.md        # the independent adversarial reviewer
    │   ├── hooks/
    │   │   ├── hooks.json                 # wires the Stop + SessionStart hooks (Layer 1)
    │   │   ├── stop-goal-loop.sh          # the self-armed goal loop (Layer 1)
    │   │   └── session-start.sh           # always-on discipline injection (SessionStart)
    │   └── output-styles/tale-mode.md     # opt-in output style (selectable via /config)
    └── tale-mode-governor/                # OPTIONAL companion (per-turn Sonnet cost)
        ├── .claude-plugin/plugin.json     # metadata (depends on tale-mode)
        └── hooks/hooks.json               # Layer 2: the read-only Sonnet governor
```

`SKILL.md` is the whole methodology and is the only file the claude.ai app needs.
Everything else adds the slash-command, sub-agent, and autonomous-loop machinery that
Claude Code uses.

## Managing / removing

It's a normal Claude Code plugin — manage it with the built-in commands (or just ask
Claude, e.g. *"remove tale mode"*, and it'll point you here):

```text
/plugin uninstall tale-mode@tale-mode             # remove the core (skill, commands, agent, loop)
/plugin uninstall tale-mode-governor@tale-mode    # remove the governor (if you installed it)
/plugin disable   tale-mode@tale-mode             # turn it off but keep it installed
/plugin update    tale-mode@tale-mode             # pull the latest
```

Uninstall is clean: it removes the plugin's files and its `enabledPlugins` entry, and never
touches the rest of your `settings.json`. (A goal-file you armed in a project, e.g.
`.claude/active-goal.json`, is harmless once the hook is gone — delete it if you like.)

## Contributing

Issues and PRs welcome. This repo is dogfooded — if you're proposing a change to
the methodology, run it through the `plan-reviewer` agent first and include what it
found (that's the [receipts](#what-makes-it-different) discipline applied to
the repo itself). Keep edits to `SKILL.md` host-agnostic; put Claude Code-specific
assets under `plugins/tale-mode/`.

## License

MIT licensed — see [`LICENSE`](LICENSE).
