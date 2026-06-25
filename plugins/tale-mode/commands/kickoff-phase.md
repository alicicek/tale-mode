---
description: Start a scoped chunk of a larger plan in a fresh session — interview the user first, then implement only that chunk.
argument-hint: <plan-file-path> <phase/chunk id>
---
**If your tooling has a plan mode, enter it now** and stay in it through the
investigate-and-confirm steps below — no edits until I approve. Read the plan at
the path in **$ARGUMENTS** (and any roadmap/README it points to) in full.
Implement only the named chunk.

**Before writing any code, interview me — but interview SHARP.** Re-verify the plan's
claims for this chunk against the actual code (the code is ground truth; the plan is a
snapshot) — and confirm any external framework/SDK/CLI setup against current docs
(Context7/web), not memory. Then **split the open decisions into two kinds and handle
them differently — never quiz me on something a senior engineer would just decide:**

- **Engineering calls → DECIDE and proceed (don't ask).** Anything settle-able from the
  code + best practice: route/file/module placement, data shape, library choice, error
  handling, where logic lives, naming, API surface. **Make the call a senior software
  engineer shipping a production app would make — industry-standard, durable, correct;
  never an MVP / prototype / temp-workaround unless I explicitly asked for one.** State
  the decision + a one-line rationale and move on. When two options trade off, first
  check whether the *best* answer **combines** them — don't present a forced either/or
  that hides a superior unified design. Escalate an engineering call to a question ONLY
  if it's genuinely hard to reverse and you're truly torn, or it secretly carries a
  product/cost choice.

- **Judgment calls → ASK (batched, ONE `AskUserQuestion` round).** Only what needs *my*
  preference, priorities, or authority: product/UX behaviour, scope or priority
  trade-offs, cost/vendor choices, anything with a business dimension, and steps only I
  can do (credentials, dashboards, go/no-go). Don't invent constraints — name the gaps.
  **Phrase every option OUTCOME-FIRST — the user flow, how it feels, the real-world
  result (upload speed, drop-off, conversion, cost) — THEN append a one-line technical
  note in parentheses for technical users (the mechanism / trade-off). Lead with the
  outcome, never the jargon: "uploads feel instant but cost a little more (optimistic
  client writes vs server-confirmed)". A non-technical owner decides on the outcome; a
  technical one still sees the how. I decide on outcomes; the code is yours.**
  Label each option's authority — **"In plan"** / **"Engineering alternative"** /
  **"Out of scope"** — and flag any MVP/temp-shortcut option *as a shortcut* (never
  present one as co-equal with the production-grade choice). Don't mark "Recommended"
  anything that contradicts the active plan.

**Follow the plan; auto-defer (and record in the plan) any in-plan item that won't fit
the session budget and regresses nothing — don't ask, just log it.** Don't re-decide
what the plan settled. If the plan's approach is wrong or a genuinely better architecture
exists, say **"recommend changing the plan"** and cite the exact line. Batch every real
question into one round; proceed on your own production-grade judgment for everything else.

Once I answer: present the concrete approach for this chunk and **get my approval
to exit plan mode** (ExitPlanMode). Only then implement on a dedicated branch, then
**prove it by running it, not by reading the diff** — use `/verify` to confirm the
chunk behaves as intended and `/run` to boot and drive the live app, whenever the
change is actually runnable (pick what fits: pure logic → `/verify` against a test;
UI/API → `/run` + a real browser/curl pass). Self-critique; run the project's
required `/code-review` on the diff plus `/security-review` for anything touching
auth/money/secrets/storage (effort/scope per the project's CLAUDE.md). **Then close
the review loop — never ship the fix delta unreviewed:** run tale-mode §5's
*fresh-eyes* pass (a clean-context sub-agent — the `plan-reviewer` agent for
high-stakes — or a `/clear`'d self-review, given only the diff + spec, framed as a
hostile senior reviewing a junior's PR, running the §5 blind-spot checklist), fix
every P0/P1, **re-review the post-fix delta in a fresh frame**, repeat until a fresh
pass finds no P0/P1.

Then **open the PR and run the cross-model loop** — the load-bearing gate, not a
courtesy (a different model catches the bug-class your own passes structurally miss):
**fetch Greptile's review** (the Greptile plugin, or `gh pr view <pr> --json
reviews,comments` / `gh api`), **fix every P0/P1 it flags, push (re-triggers
Greptile), poll for its re-review, and repeat until Greptile reports zero P0/P1.**

**Keep looping the gate yourself** (review → fix → re-fetch Greptile → re-review) until
it converges to zero P0/P1 — don't stop at the first pass. You can't start `/goal` (it's
a user command); when the gate is worth an enforced backstop, surface it — the user can
wrap the session in `/goal: the fresh-context adversarial review AND Greptile's PR review
both report zero P0/P1 (verdicts pasted) and every finding addressed.` Gate on the clean
reviews, not green tests; cap the rounds. Before
declaring done, **emit a DONE/MISSING table** for the gate (one row each: `/verify`,
`/run`, `/code-review`, `/security-review`, fresh-eyes review, Greptile clean, plan
progress updated) so a skip shows as a MISSING cell, not a silent omission. **If a
behavioral check can't run yet (needs external provisioning), don't skip it silently —
record it as a named, owned deferral in the plan's progress and treat the chunk as
not-done until discharged.** Merge only on my go-ahead. When done, update the plan
file's progress with a one-line outcome note (commit hash + any drift). Don't start any later chunk. If new
questions arise mid-build, pause and ask rather than guess.
