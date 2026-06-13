---
description: Start a scoped chunk of a larger plan in a fresh session — interview the user first, then implement only that chunk.
argument-hint: <plan-file-path> <phase/chunk id>
---
**If your tooling has a plan mode, enter it now** and stay in it through the
investigate-and-confirm steps below — no edits until I approve. Read the plan at
the path in **$ARGUMENTS** (and any roadmap/README it points to) in full.
Implement only the named chunk.

**Before writing any code, interview me.** Re-verify the plan's claims for this
chunk against the actual code (the code is ground truth; the plan is a snapshot).
Then use **AskUserQuestion** to surface — in ONE batched round — every genuine
question, assumption, ambiguity, gap, or decision-with-trade-offs: anything the
plan is vague or silent on, anywhere the code has drifted, any assumption you'd
otherwise make silently, anything that could change behavior, and any step that
needs me (credentials, dashboards, go/no-go). Don't invent constraints — name the
gaps. Only proceed on sensible defaults for genuinely trivial things; batch the
questions.

Once I answer: present the concrete approach for this chunk and **get my approval
to exit plan mode** (ExitPlanMode). Only then implement on a dedicated branch,
**prove it by running it** (not just the diff), self-critique, and — for
high-stakes work — run the `plan-reviewer` agent. Hit the verification gate, then
open a PR; merge only on my go-ahead. When done, update the plan file's progress with a one-line
outcome note (commit hash + any drift). Don't start any later chunk. If new
questions arise mid-build, pause and ask rather than guess.
