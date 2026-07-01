# Architecture — how Tale Mode works

The README is the tour; this is the map. It explains the system design, how each part
works, how everything gets loaded, and the reasoning behind the trade-offs — including
the parts that are deliberately modest.

## The thesis

Strong models don't fail on hard tasks because they lack capability — they fail because
they rush. They trust their memory of a file instead of re-reading it, review their own
work from inside their own frame, and declare "done" off a clean diff without running
anything. Tale Mode attacks that with three layers, built on one observation:
**instructions can be ignored by a rushing model, but hooks can't.** Words drift; hooks
don't.

```text
┌─ LAYER A · INSTRUCTIONS (words the model reads) ────────────────────┐
│  skills/tale-mode/SKILL.md       the method — the 8-step loop       │
│  commands/ + phase skills        plan-phase · kickoff-phase         │
│  output-styles/tale-mode.md      opt-in stronger variant            │
│  helper skills                   trust · seed-gates · end-phase     │
├─ LAYER B · ENFORCEMENT (deterministic bash hooks) ──────────────────┤
│  session-start.sh    injects 3 core rules into EVERY session        │
│  mark-phase.sh       records "a deliberate build phase started"     │
│  stop-goal-loop.sh   THE LOOP — a turn cannot end until a real      │
│                      shell check passes                             │
├─ LAYER C · REVIEW (eyes that aren't the author's) ──────────────────┤
│  agents/plan-reviewer.md    adversarial reviewer (different model)  │
│  tale-mode-governor         optional: read-only reviewer that fires │
│                             only when the loop is stuck             │
└──────────────────────────────────────────────────────────────────────┘
```

Layer C exists because self-review has a hard ceiling: a model fixes an error instantly
when it's framed as someone else's code, yet misses the same error in its own output.
More effort can't close that gap — only a fresh context can, and a *different model*
closes it further (different training, different blind spots).

## How it loads

1. `/plugin install tale-mode@tale-mode` registers the plugin's `hooks.json`. Nothing
   else is touched — no settings surgery, no permissions edits.
2. On **every session start** (including after `/clear` and after compaction),
   `session-start.sh` prints ~200 tokens of the three core rules — verify against ground
   truth, foundation-first, two-strike — into the model's context. This is the always-on
   floor: nothing to remember, nothing to arm.
3. The **skill** loads on demand — say "tale mode", or the model self-activates it when
   the work matches its description.
4. The **Stop hook** runs at every turn-end but is engineered to be a silent
   few-millisecond no-op unless something armed it. Normal turns never feel it.

## The autonomous loop, in detail

Claude Code's `/goal` is user-only. Tale Mode gives the *agent* a loop it can start
itself:

```text
agent starts a hard, verifiable task
        │
        ▼
writes .claude/active-goal.json        { goal, check: "npm test | grep -q PASSED",
        │                                rounds: 0, max_rounds: 25, needs_user: null }
        ▼
agent tries to end its turn ──► Stop hook runs `check`
        │                               │
        │        fails ◄────────────────┤────────────► passes
        ▼                               │                  ▼
turn BLOCKED, coaching injected         │        goal-file cleared,
(foundation-first · two-strike ·        │        turn ends — actually done
 "don't band-aid the check")            │
        │                               │
        └── another turn ───────────────┘   (each round: one JSONL line to
                                             .claude/tale-mode.log)
```

The model cannot say "done" until reality agrees. Most of the code is the safety
engineering that makes this shippable:

- **Bounded.** A `max_rounds` ceiling, plus an optional no-progress stop
  (`TALE_NO_PROGRESS_N`): N consecutive rounds failing with a byte-identical signature
  disarm the loop — an unchanged failure means it's anchored, not working.
- **Fail-open, everywhere.** Can't persist state, no `jq`, garbage input, unwritable
  directory — every failure path *allows* the turn rather than trapping it. The loop can
  annoy you by stopping; it can never imprison you.
- **Pausable.** `needs_user` lets the agent end the turn to ask for a secret, a login,
  or a go/no-go, then resume — instead of grinding the impossible.
- **Session-scoped.** Goal-files and phase markers are keyed by session id, so one
  session's loop can never trap another session in the same repo. Stale files from
  crashed sessions get reaped.
- **Auditable.** Each round appends one JSON line (round, check, verdict, exit code,
  output tail) to a local log. No network, ever.

## The trust model (why gates need a human blessing)

The v2 upgrade lets a repo **commit** its gates (`.claude/tale-mode.json` — e.g. "run
the test suite") so enforcement doesn't depend on the agent remembering to arm anything.
During a deliberate `kickoff-phase`, with uncommitted changes, the Stop hook runs those
gates automatically.

But committed gates are arbitrary shell shipped inside a repo — so they never execute
until *you* record the file's sha256 in `~/.claude/tale-mode-trust`. The hook can read
that store; it can never write it, and neither can the agent. Change one byte of the
config and the hash no longer matches: the gates go inert until a human re-blesses them.
Trusting code is a human act. The same principle covers the Codex opt-in
(`~/.tale-mode-allow-cwd-root`): capabilities that widen the blast radius live in *your*
home directory, written only by you.

## Cross-platform notes

Codex loads Claude-format plugins, with three differences Tale Mode absorbs:

- No user slash commands → the phase workflows ship twice, as commands (Claude Code) and
  as skills (Codex). A drift-guard test keeps the twins' load-bearing text in sync.
- No trusted project-root env for hooks → the loop stays inert on Codex until the
  one-time `~/.tale-mode-allow-cwd-root` opt-in.
- A skill invocation may not carry the kickoff trigger text → the kickoff skill writes a
  *pending* phase marker that the Stop hook claims and session-scopes at the first
  turn-end.

All three paths were verified against live sessions — the receipts are in
[`codex-governor-spike.md`](codex-governor-spike.md) and the test suites.

## What it costs, and what it's honestly worth

The default install costs ~200 tokens of context per session and a no-op hook per
turn-end. The heavy machinery only runs when invoked.

The candid 80/20: the **discipline layer** (skill + always-on rules + the
plan-phase → kickoff-phase pipeline) is most of the value — it's a checklist against
documented failure modes, and checklists work. The **loop** is a seatbelt: proven to
function, most valuable on the rare bad day, not a daily multiplier — capable models
usually self-regulate. The **governor** is the most situational piece; it fires only
when a loop is genuinely stuck. That ordering is deliberate: the cheap, always-on parts
carry the weight, and everything expensive is opt-in.

## Model pairing

Tale Mode is a two-role system, and the roles want *different* models:

- **The worker** — the strongest reasoning model available (the method spends capability
  on fan-out, verification, and adversarial passes). Effort `xhigh` as the default;
  reserve `max` for the single hardest pass. The returns come from the orchestration,
  not the dial.
- **The reviewer** — deliberately a different model than the worker, so their blind
  spots don't overlap. This repo's own history includes a bug that self-review,
  same-model review, and a code-review pass all missed — and a cross-model reviewer
  caught. The deterministic gate (a real test's exit code) stays the final arbiter,
  because it has no blind spots at all.

Worker + cross-model reviewer + deterministic gate: three judges that don't share
failure modes. That's the whole design in one sentence.
