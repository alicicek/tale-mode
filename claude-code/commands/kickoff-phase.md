---
description: Start a scoped chunk of a larger plan in a fresh session — interview the user first, then implement only that chunk.
argument-hint: <plan-file-path> <phase/chunk id>
---
**If your tooling has a plan mode, enter it now** and stay in it through the
investigate-and-confirm steps below — no edits until I approve. Read the plan at
the path in **$ARGUMENTS** (and any roadmap/README it points to) in full.
Implement only the named chunk.

**Before writing any code, interview me.** Re-verify the plan's claims for this
chunk against the actual code (the code is ground truth; the plan is a snapshot) — and confirm any external framework/SDK/CLI setup against current docs (Context7/web), not memory.
Then use **AskUserQuestion** to surface — in ONE batched round — every genuine
question, assumption, ambiguity, gap, or decision-with-trade-offs: anything the
plan is vague or silent on, anywhere the code has drifted, any assumption you'd
otherwise make silently, anything that could change behavior, and any step that
needs me (credentials, dashboards, go/no-go). Don't invent constraints — name the
gaps. Only ask about genuine forks; do not re-decide items the plan already
settled. For every multiple-choice option, label its authority as **"In plan"**,
**"Engineering alternative"**, or **"Out of scope"**. Do not mark an option
"Recommended" if it contradicts the active plan. If you want to recommend
changing the plan, explicitly say "recommend changing the plan" and cite the
exact plan line being overridden. Only proceed on sensible defaults for
genuinely trivial things; batch the questions.

Once I answer: present the concrete approach for this chunk and **get my approval
to exit plan mode** (ExitPlanMode). Only then implement on a dedicated branch, then
**prove it by running it, not by reading the diff** — use `/verify` to confirm the
chunk behaves as intended and `/run` to boot and drive the live app, whenever the
change is actually runnable (pick what fits: pure logic → `/verify` against a test;
UI/API → `/run` + a real browser/curl pass). Self-critique; run the project's
required `/code-review` on the diff plus `/security-review` for anything touching
auth/money/secrets/storage (effort/scope per the project's CLAUDE.md); and for
high-stakes work run the `plan-reviewer` agent. **If a behavioral check can't run yet
because it needs external provisioning (services, credentials, infra), don't skip it
silently — record it as a named, owned deferral in the plan's progress and treat the
chunk as not-done until it's discharged.** Hit the verification gate, then open a
PR; merge only on my go-ahead. When done, update the plan file's progress with a one-line
outcome note (commit hash + any drift). Don't start any later chunk. If new
questions arise mid-build, pause and ask rather than guess.
