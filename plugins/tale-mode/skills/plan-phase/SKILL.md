---
name: plan-phase
description: Plan a large, multi-phase feature to a high bar — verify against the code, receipts on every decision, an adversarial fresh-eyes review, and runnable verification gates, decomposed into independently-shippable phases. Invoke explicitly when starting a big multi-session build (the cross-platform form of the /tale-mode:plan-phase command; on Codex, name the task in your prompt).
---

# Plan a phase (high bar)

> **Cross-platform note.** This is the skill form of the `/tale-mode:plan-phase` Claude Code
> command, for hosts where slash commands don't exist (e.g. Codex). The two are kept in sync —
> if you edit one, mirror the other. On Codex there is no `$ARGUMENTS`: take **the task to plan
> from the user's prompt**. If your host has a plan mode, enter it.

Plan the user's task at a high bar. Do not skip a step:

1. **Verify, don't trust.** Spawn a read-only sub-agent (Claude Code: an Explore agent; Codex: a
   sub-agent) to read the relevant code and sources; confirm every claim you'll rely on; cite
   `file:line`. Correct any stale assumption explicitly ("the brief says X; the code shows Y at
   `<file:line>`"). For any external framework / library / SDK / CLI — especially fast-moving or
   RC ones — confirm the CURRENT setup against official docs (Context7 / web), not training memory.

2. **Decisions with receipts.** A table `Decision | Source`, where Source is a verbatim quote from
   the user, an answer you asked for, or "my judgment — rationale: …". Never inscribe a constraint
   nobody gave you. If the task came from an open-ended discussion with no written brief, first
   distil that conversation's conclusions into the receipts table — don't plan against un-captured
   intent.

3. **Ask the real forks.** Ask the user about genuine, load-bearing choices you can't resolve from
   the task / code / a sensible default — batched into one round. Label each option by authority:
   **"In plan"**, **"Engineering alternative"**, or **"Out of scope"**. Don't mark an option
   "Recommended" if it contradicts the active plan; to override the plan, say "recommend changing
   the plan" and cite the exact line.

4. **Adversarial review — fresh eyes, looped.** Run a *hostile, fresh-context* reviewer on your
   draft (Claude Code: the `plan-reviewer` agent; Codex: a fresh sub-agent framed as a jaded senior):
   "try to break this plan — what's stale vs the code, what's a design hole, what's the worst-case
   input, what will the verification miss?" Fold every confirmed finding in with an ID (C1, C2, …),
   then **re-run it on the revised plan** until a fresh pass surfaces nothing material (cap the
   rounds; gains saturate fast). This is where design holes get caught before they cascade.

5. **Invariants.** List what must not break (frozen contracts, do-not-touch, security / privacy /
   data / money) and assert each in the verification section.

6. **Decompose & sequence — size to sessions.** If the task is larger than one sitting, split it
   into independently-shippable phases — each sized to one session / one PR / one coherent
   verify-loop, with its own done-criteria, gate, and rollback. Keep each phase thin (intent +
   gate), not step-by-step — the executor re-derives specifics against live code at kickoff. Order
   foundation-first, then independent fan-out. Emit a progress tracker and a kickoff cue per phase.

7. **Runnable gates.** Exact commands with expected output — never "test it" — and note what each
   check can't catch. For each phase name the behavioral check that proves it works (Claude Code:
   `/verify`; `/run` for anything user-facing — Codex: run the test / drive the app yourself), and,
   for phases touching auth / data / money / security / storage, the review the executor runs before
   the PR (Claude Code: `/code-review` + `/security-review`; Codex: a free fresh-context sub-agent
   review + the `codex-security` skills). A cross-model metered reviewer (Greptile / CodeRabbit) is
   owner-triggered — surface it, never auto-run it. Flag any check blocked on not-yet-provisioned
   services as a deferral the kickoff carries.

8. **Rollback + out-of-scope + known-untestable.** Name them.

State the risk tier up front (touches auth / data / money / security → full ceremony incl. the §4
review; otherwise lighter). Write the plan to a durable file — label each phase so the kickoff
workflow can target it by name. Then request approval.
