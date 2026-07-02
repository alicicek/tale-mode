---
description: Start a scoped chunk of a larger plan in a fresh session — interview the user first, then implement only that chunk.
argument-hint: <plan-file-path> <phase/chunk id>
---
**If your tooling has a plan mode, enter it now** and stay in it through the
investigate-and-confirm steps below — no edits until I approve. **Recon prompt-hygiene
(plan mode prompts on any shell it can't prove read-only):** prefer the dedicated read
tools (Read/Grep/Glob) over shell; keep shell recon to plain single-purpose read-only
commands — `ls`/`cat`/`grep`/`git log` and simple chains of them auto-approve via the
bundled plan-mode hook — and route loop-heavy sweeps through read-only sub-agents, so I'm
not walled with permission prompts. Read the plan at
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
to exit plan mode** (ExitPlanMode). Only then implement on a dedicated branch. **Exiting
plan mode authorizes EDITING, not committing — get my explicit sign-off before EVERY
`git commit` and EVERY push (pause and summarize what you'd commit each time).** Then
**prove it by running it, not by reading the diff** — use `/verify` to confirm the
chunk behaves as intended and `/run` to boot and drive the live app, whenever the
change is actually runnable (pick what fits: pure logic → `/verify` against a test;
UI/API → `/run` + a real browser/curl pass). Self-critique; run the project's
required `/code-review` on the diff plus `/security-review` for anything touching
auth/money/secrets/storage (effort/scope per the project's CLAUDE.md). **These are
bundled Claude Code skills — invoke them via the Skill tool (`/code-review
<base>...<branch>` reviews the local diff, no PR needed); actually run them, don't
substitute a hand-rolled review.** **Run the review fan-out lean:** route a large
finder/reviewer set through a Workflow (or have each agent return a terse verdict), keep
raw logs / JSON / PR-comment dumps OUT of your context — extract the finding first — and
batch independent calls into one round-trip; a hand-spawned fan-out that reports long
findings back into the window is the dominant context cost of a review session. **Then close
the review loop — never ship the fix delta unreviewed:** run tale-mode §5's
*fresh-eyes* pass (a clean-context sub-agent — the `plan-reviewer` agent for
high-stakes — or a `/clear`'d self-review, given only the diff + spec, framed as a
hostile senior reviewing a junior's PR, running the §5 blind-spot checklist), fix
every P0/P1, **re-review the post-fix delta in a fresh frame**, repeat until a fresh
pass finds no P0/P1.

Then, **only on my go-ahead, open the PR** — opening or pushing a PR triggers CI and can
trigger metered reviewers, so never open or push without my sign-off. A cross-model review
is the strongest §5 pass (a different model catches the bug-class your own passes
structurally miss) — **but metered bots (Greptile, CodeRabbit, …) are CREDIT-METERED and
OWNER-TRIGGERED: do NOT auto-run them, do NOT comment `@greptile review`, and do NOT
push-loop them (every push to an open PR re-triggers the bot = real money). Auto-running a
metered tool is the same class of mistake as any outward-facing/cost-incurring action —
confirm first.** Tell me a cross-model pass is available and let me decide whether/when to
spend it. If I run it, **fix every P0/P1 it flags, then ask before pushing** (I control each
re-trigger) and batch fixes into a single push. Gate on the clean reviews, not green tests;
cap the rounds. You can't start `/goal` (it's a user command); when an enforced backstop is
worth it, surface it — I can wrap the session in `/goal: the fresh-context adversarial review
reports zero P0/P1 (verdict pasted) and every finding addressed.` Before
declaring done, **emit a DONE/MISSING table** for the gate (one row each: `/verify`,
`/run`, `/code-review`, `/security-review`, fresh-eyes review, cross-model review
(owner-triggered — mark N/A if I didn't run it), plan progress updated) so a skip shows as
a MISSING cell, not a silent omission. **If a
behavioral check can't run yet (needs external provisioning), don't skip it silently —
record it as a named, owned deferral in the plan's progress and treat the chunk as
not-done until discharged.** Merge only on my go-ahead. When done, update the plan
file's progress with a one-line outcome note (commit hash + any drift). Don't start any later chunk. If new
questions arise mid-build, pause and ask rather than guess.
