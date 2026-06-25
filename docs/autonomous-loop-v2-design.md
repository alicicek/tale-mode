# Autonomous Loop v2 — Deterministic, Self-Arming Convergence

> Design doc. Proposes a ground-up rework of the v1 single-goal-file loop. Status: **proposed
> (2026-06-25)**, not yet built. The v1 loop (`docs/autonomous-loop-design.md`,
> `plugins/tale-mode/hooks/stop-goal-loop.sh`) ships today; this supersedes it.

## Why v2 — what v1 got wrong (evidence, not theory)

v1 = a single `<project>/.claude/active-goal.json` that the **agent writes** to arm the loop.
Three failures surfaced in real use:

1. **Forgettable arming — the load-bearing failure.** In a real T4 build, L1 (the gate) and L2
   (the governor) were installed and default-on, yet sat **inert the entire phase**: the agent
   never wrote the goal-file, so the loop never engaged. It fell back to *"trust me, I ran the
   review loop manually."* An autonomous loop you must *remember to arm* is not autonomous —
   and an LLM will forget. *(Verified: the T4 session's own report; this repo's hook code.)*
2. **Cross-session / stale collision.** The goal-file is **one per project and not session-scoped**.
   A goal armed by a session that crashes or ends mid-loop persists on disk; the *next* session in
   that repo reads it and gets trapped on a stale check that was never theirs, and two concurrent
   sessions fight over the one file. *(Verified: `stop-goal-loop.sh` keys only on
   `$CLAUDE_PROJECT_DIR/.claude/active-goal.json` with no session id; `session_id` is present in the
   Stop-hook input but the script reads `$INPUT` and never parses it — line 33.)*
3. **One-at-a-time, no backlog.** One file holds one goal. Deferred work ("do it later") has no
   home — which is exactly the silent-drop problem.

## The model: a reconciliation loop (borrowed from the best autonomous systems)

A goal is a **declared desired state + a convergence check**; the loop **reconciles** actual → desired
until the check passes. This is the canonical pattern for systems that "keep going until converged,"
and we borrow it deliberately:

- **Kubernetes controllers / Terraform** — a *declarative desired state* + a controller that
  continuously drives actual toward it. → our committed config is the desired state; the Stop hook is
  the controller.
- **Job queues (SQS / Sidekiq) — leases / visibility timeouts** — work is *leased* to a worker; a dead
  worker's lease expires and the work is reclaimed, never stuck. → session-scoping + TTL reaping for
  ephemeral goals (fixes the stale collision).
- **`make` / CI gates / the agile "definition of done"** — a committed, objective "is it satisfied?"
  check. → `.claude/tale-mode.json`.

## Architecture — three planes

### 1. Declarative plane — `.claude/tale-mode.json` (committed)
The deterministic spine. Because it's **committed**, it is *always present* — the loop never depends on
the agent remembering to arm anything.
```json
{
  "gates": ["npm test --silent", "npm run -s typecheck"],
  "doneWhen": "gatesGreen && deferralsAccountedFor",
  "deferrals": ".claude/deferrals.json"
}
```

### 2. Reconciler plane — the Stop hook (L1) + governor (L2)
On every turn-end:
- **Auto-arm (deterministic — no agent memory):** active only while a **phase is in progress** (a
  marker the `kickoff-phase` command sets — a deliberate phase start, *not* a per-decision agent
  choice) **and** there are **uncommitted tracked changes** (`git status --porcelain`).
- **Reconcile:** run the committed `gates` + the deferral-hygiene check.
  - Converged (gates green **&&** no silent drops) → allow the stop.
  - Not converged → `{"decision":"block"}` — keep going. Bounded by `max_rounds` + fail-open
    (v1's two self-contained safeties, kept verbatim).
- **Escape hatches:** the agent sets `needs_user` (pause to ask), the phase ends (PR opened/merged →
  marker clears), or `max_rounds`.
- **L2 governor** at `rounds >= 2`: reads ground truth, breaks anchoring (unchanged).

### 3. Backlog plane — `.claude/deferrals.json` (committed)
The "build them up" queue: parked goals / deferred scope — durable, committed, **cross-session by
design**. The `doneWhen` policy requires every phase scope-item to be *built* **or** have an entry here
(the deferral done-gate). "Discharge" = promote an entry back to active work later.

## Identity & staleness (fixes problem 2)
- The committed config + backlog are **intentional repo files** — no transient stale-leak between
  sessions.
- Any **ephemeral ad-hoc goal** (the explicit "drive to this *specific* target" power-mode, retained
  for cases a committed gate can't express) is **session-scoped**: tagged with the arming session's
  `session_id` (from the hook input), and the hook honors only the *current* session's goal, reaping or
  ignoring others (TTL). A dead session's goal can never trap a new one.

## What this buys (the superpower)
A coding agent that **cannot declare victory while the objective gates are red or scope was silently
dropped**, and that drives itself to green without supervision — automatically, deterministically,
adversarially-governed. The model's *judgment* does the work; the deterministic loop *guarantees* it
can't stop short or forget to start. That is the autonomy bar worth aiming for.

## The one decision to confirm
**When does auto-arm enforce?** Proposed: only while a *phase marker* is set (kickoff sets it) **and**
there are uncommitted changes — so casual/exploratory sessions are never taxed and only real build
phases get enforced convergence. Alternative: always-on whenever `gates` are configured (simpler, but
would block any session that ends with red gates). **Recommendation: phase-scoped.**

## Build plan (phased — each independently shippable, each fully gated + plan-reviewer'd)
1. **Session-scope + reap the ephemeral goal-file** — fixes the stale-collision bug; small,
   self-contained, design-robust (needed in every version).
2. **The committed `.claude/tale-mode.json` + the reconciler auto-arm** — the deterministic spine.
3. **The deferral backlog + done-gate** — the silent-drop guarantee.
4. **Docs + the 31-test suite extended + SKILL/kickoff wiring** (phase marker; clarify the goal-file
   loop is *separate from the built-in `/goal`* — a conflation that bit a careful session).
