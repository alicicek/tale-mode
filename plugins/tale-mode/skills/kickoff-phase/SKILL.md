---
name: kickoff-phase
description: Build ONE scoped phase of an existing multi-phase plan in a fresh session — re-verify the plan against the live code, interview the user sharply on real forks, then implement only that phase behind plan-mode approval with runnable verification and a fresh-eyes review. Invoke explicitly when starting a phase (the cross-platform form of /tale-mode:kickoff-phase; on Codex, name the plan-file + phase in your prompt). On Claude Code, use the /tale-mode:kickoff-phase command instead of this skill.
---

# Kick off a phase

> **Cross-platform note.** This is the skill form of the `/tale-mode:kickoff-phase` Claude Code
> command, for hosts where slash commands don't exist (e.g. Codex). The two are kept in sync — if
> you edit one, mirror the other. On Codex there is no `$ARGUMENTS`: take **the plan-file path and
> the phase/chunk id from the user's prompt**.
>
> **Arm the phase loop (skill-invoked hosts only).** When this runs as a *skill*, the phase-marker
> hook may never see the kickoff (it matches the prompt text, which a prose invocation may not
> carry), so write the pending marker yourself — your first action once you're allowed to write
> (immediately, or right after plan approval if your host blocks writes in plan mode), **run from
> the project root** (the Stop hook only looks for it there):
>
> ```bash
> [ -f .claude/tale-mode.phase.pending.json ] || printf '%s\n' \
>   '{"session":"pending","rounds":0,"max_rounds":50,"needs_user":null}' \
>   > .claude/tale-mode.phase.pending.json
> ```
>
> The Stop hook claims that file for your session at the first turn-end and then enforces the
> committed `.claude/tale-mode.json` gates while the tree is dirty — IF the user has trusted that
> config's content-hash (inert otherwise; the `trust` skill has the commands — surface them, never
> run them). For a goal the committed gates don't cover, additionally write
> `.claude/active-goal.json` (the ad-hoc loop). On Claude Code the `/tale-mode:kickoff-phase`
> command arms this automatically — don't double-arm there.

**If your host has a plan mode, enter it now** and stay in it through the investigate-and-confirm
steps below — no edits until the user approves. Read the named plan file (and any roadmap/README it
points to) in full. Implement only the named chunk.

**Before writing any code, interview the user — but interview SHARP.** Re-verify the plan's claims
for this chunk against the actual code (the code is ground truth; the plan is a snapshot), and
confirm any external framework/SDK/CLI setup against current docs (Context7/web), not memory. Then
split the open decisions and handle them differently:

- **Engineering calls → DECIDE and proceed (don't ask).** Anything settle-able from the code + best
  practice: file/module placement, data shape, library choice, error handling, naming, API surface.
  Make the call a senior engineer shipping production would make — never an MVP/temp-workaround unless
  explicitly asked. State the decision + a one-line rationale and move on. When two options trade off,
  first check whether the *best* answer combines them. Escalate to a question only if it's genuinely
  hard to reverse and you're torn, or it secretly carries a product/cost choice.
- **Judgment calls → ASK (batched, one round).** Only what needs the user's preference, priorities, or
  authority: product/UX behaviour, scope/priority trade-offs, cost/vendor choices, and steps only they
  can do (credentials, dashboards, go/no-go). Phrase every option **outcome-first** (the real-world
  result), then a one-line technical note in parens. Label each option's authority — **"In plan"** /
  **"Engineering alternative"** / **"Out of scope"** — and flag any shortcut *as a shortcut*.

**Follow the plan; auto-defer (and record in the plan) any in-plan item that won't fit the session
budget and regresses nothing — don't ask, just log it.** Don't re-decide what the plan settled. If
the plan's approach is wrong, say **"recommend changing the plan"** and cite the exact line. Batch
every real question into one round.

Once the user answers: present the concrete approach and **get approval to start editing** (exit plan
mode). Only then implement, on a dedicated branch. **Approval authorizes EDITING, not committing — get
explicit sign-off before EVERY commit and EVERY push** (pause and summarize what you'd commit each
time).

Then **prove it by running it, not by reading the diff** (Claude Code: `/verify` to confirm behavior,
`/run` to boot/drive the live app, whenever runnable — Codex: run the test / drive the app yourself and
observe). Self-critique; then run the §5 review for the diff: Claude Code → `/code-review` plus
`/security-review` for anything touching auth/money/secrets/storage; Codex → a **free fresh-context
sub-agent** review (framed hostile) plus the `codex-security` skills for those surfaces. **Close the
review loop — never ship the fix delta unreviewed:** fix every P0/P1, **re-review the post-fix delta in
a fresh frame**, repeat until a fresh pass finds no P0/P1.

A **cross-model metered** reviewer (Greptile / the CodeRabbit `code-review` skill) is the strongest §5
pass — **but it is OWNER-TRIGGERED and credit-metered: do NOT auto-run it, comment `@…`, or push-loop
it (every push to an open PR re-triggers it = real money).** Surface that it's available; let the user
decide. If they run it, fix every P0/P1, then ask before pushing (batch fixes into one push).

Before declaring done, **emit a DONE/MISSING table** for the gate (one row each: behavior check,
review, security review, fresh-eyes review, cross-model review (owner-triggered — mark N/A if not run),
plan progress updated) so a skip shows as a MISSING cell, not a silent omission. **If a behavioral
check can't run yet** (needs external provisioning), record it as a named, owned deferral in the plan's
progress and treat the chunk as not-done until discharged. Merge only on the user's go-ahead. When done,
update the plan file's progress with a one-line outcome (commit hash + any drift). Don't start any later
chunk. If new questions arise mid-build, pause and ask rather than guess.
