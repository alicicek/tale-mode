---
description: Plan a task to a high bar — verify against the code, receipts on every decision, adversarial review, runnable verification gates.
argument-hint: <the task or feature to plan>
---
Plan **$ARGUMENTS** at a high bar. If your tooling has a plan mode, enter it. Do
not skip a step:

1. **Verify, don't trust.** Launch a read-only/Explore agent to read the relevant
   code and sources; confirm every claim you'll rely on; cite file:line. Correct
   any stale assumption explicitly ("the brief says X; the code shows Y at
   `<file:line>`"). **For any external framework / library / SDK / CLI you'll build on** — especially fast-moving or RC ones — confirm the CURRENT setup against official docs (Context7 / web), not training memory; scaffold commands, adapter conventions, and build-output paths are top causes of "looked right, didn't run".
2. **Decisions with receipts.** A table `Decision | Source`, where Source is a
   verbatim quote from the user, an answer you asked for, or
   "my judgment — rationale: …". Never inscribe a constraint nobody gave you.
   If the task came from an open-ended discussion with no written brief, first
   distil that conversation's conclusions into the receipts table (or a short brief
   file) — don't plan against un-captured intent; the plan is only as sound as the
   receipts it cites.
3. **Ask the real forks.** Use AskUserQuestion for genuine, load-bearing choices
   you can't resolve from the task / code / a sensible default — batched. Label
   each option by authority: **"In plan"**, **"Engineering alternative"**, or
   **"Out of scope"**. Do not mark an option "Recommended" if it contradicts the
   active plan. If you want to recommend changing the plan, explicitly say
   "recommend changing the plan" and cite the exact plan line being overridden.
4. **Adversarial review.** Run the `plan-reviewer` agent on your draft; fold every
   confirmed finding into the plan with an ID (C1, C2, …) so it's traceable.
5. **Invariants.** List what must not break (frozen contracts, do-not-touch,
   security / privacy / data / money) and assert each in the verification section.
6. **Decompose & sequence — size to sessions.** If the task is larger than one
   sitting, split it into independently-shippable phases — each sized to one
   session / one PR / one coherent verify-loop, with its own done-criteria, gate,
   and rollback. A phase you can't finish *and* verify in a single session is too
   big; split it. Keep each phase thin (intent + gate), **not** step-by-step — the
   executor re-derives specifics against live code at kickoff. Order them
   foundation-first (the dependency root, gated green), then independent fan-out
   where parallelizable. For a multi-phase plan, emit a progress tracker and a
   `/kickoff-phase <this-file> "Phase N"` cue per phase.
7. **Runnable gates.** Exact commands with expected output — never "test it" — and
   note what each check can't catch. A clean diff is not evidence; run it.
8. **Rollback + out-of-scope + known-untestable.** Name them.

State the risk tier up front (touches auth / data / money / security → full
ceremony incl. the §4 review; otherwise lighter). Write the plan to a durable
file — label each phase so `/kickoff-phase` can target it by name. Then request
approval.
