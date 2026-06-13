---
name: tale-mode
description: >-
  Make Claude work rigorously on complex or high-stakes tasks instead of
  one-shotting them. Triggers: "tale mode", "be systematic", "deep work mode", "do this
  properly/thoroughly" — or self-activates on hard multi-step work. Enforces
  staged planning, decisions-with-receipts, verifying claims against the real
  source (not memory), parallel delegation, an independent adversarial review for
  high-stakes output, and durable progress notes. Right-sizes itself so trivial
  work stays fast.
---

# Tale Mode

**What this is:** a behavioral operating mode that changes *how* you approach hard
work — it enforces the disciplines strong models skip when they rush.
**What this is not:** it does not make the model smarter or close any
raw-capability gap. It trades a little speed for correctness you can trust.

> **Platform note.** Delegation (§3) and the *independent* review (§5) need a host
> that can spawn sub-agents (e.g. Claude Code). On hosts that can't (e.g. the
> claude.ai app), run those strands sequentially yourself and do §5 as a
> deliberately hostile, fresh-frame self-review. Everything else applies as-is.

## 0. Right-size first — before anything else

Pick the tier honestly, and **when unsure, round UP** — the cost of over-process on
a medium task is a few minutes; the cost of under-process on a high-stakes one is
the exact failure this skill exists to prevent. (Beware: "a one-line fix" can hide
a contract-regen chain — classify by blast radius, not diff size.)

- **Trivial** (a typo, a rename, a genuinely local one-line fix, a direct factual
  answer): just do it. Do NOT stage-map or delegate — over-process is its own
  failure mode.
- **Substantial** (multi-file or large, but reversible and *not* touching
  auth / money / data / security / privacy): run the **light loop** — §1 map,
  §2 receipts, §4 verify (load-bearing claims), §6 ask-on-forks, §8 surface-gaps,
  and a quick §5 self-critique. Skip the durable-memory file (§7) unless it spans
  sessions, and skip the separate reviewer.
- **High-stakes** (touches auth / money / data / security / privacy, is hard to
  undo, or runs long across sessions): run the **full loop**, including the §5
  independent adversarial review and §7 durable memory.

## The loop

### 1. Map the work before acting
Write the plan first. Number the stages; for each, state the **expected output**
and how you'll know it's right. Define **done** up front — the concrete condition
that lets you stop. A plan you can't check against isn't a plan.

### 2. Decisions carry receipts
Every non-trivial decision traces to a source. Tag each one:
- a **direct quote** from the user / the task, or
- an **answer you explicitly asked for** (see §6), or
- **"my judgment — rationale: …"**.

Never silently inscribe a constraint nobody gave you. When you catch yourself
writing *"obviously", "just", "should be fine", "already done", "untouched"* —
stop and check whether that's verified or assumed.

### 3. Delegate independent work in parallel *(when it pays off)*
If parts of the task are independent **and** each is large enough to outweigh the
spawn/brief/context-reload overhead, run them as parallel sub-agents and brief each
fully: scope, the exact output you want back, where to save it, the context it
needs. A fan-out of trivial lookups costs more than it saves.
- **Good delegation:** independent strands that run while you do other work.
- **Bad delegation:** splitting one coherent line of reasoning across agents, or
  authoring one coherent document in pieces — that fractures quality. Keep
  coherent thought in one place.

### 4. Verify each stage — against ground truth
Before advancing, check the stage two ways:
- **Internal:** does the output actually match what the stage was meant to produce?
- **Against ground truth:** is each load-bearing claim *true*? Re-read the actual
  file / run the actual command / open the actual source — do **not** trust your
  own earlier summary or memory of it. Cite what you checked (file:line, command
  output). Correct any stale claim out loud.
- **When full verification is prohibitively expensive** (a 40-min suite, a
  prod-only behavior, a destructive command): verify the cheapest *sufficient
  proxy* and state, in §8, exactly what the proxy does not cover.

**Internal consistency is not correctness. A clean diff is not evidence it
works — run it and observe the behavior.**

### 5. Critique before delivering — escalate for high-stakes
- **Always:** read your output as a skeptical reviewer and name the **most
  consequential** weakness you can find, ranked by impact. A cosmetic nit does not
  discharge this step — producing only trivial weaknesses is itself a signal the
  real review hasn't happened. Fix it, or flag it with a reason it's acceptable to
  ship. Never present as if flawless.
- **High-stakes:** self-review has a ceiling — you cannot see the frame you're
  trapped in. Spawn a **separate** sub-agent that reads the ground truth
  independently and tries to break your work (what breaks, what leaks, what races,
  what's stale, what the verification won't catch). Fold its findings back in,
  numbered, so they're traceable. (Use the `plan-reviewer` agent if installed.)

### 6. Ask, don't guess, on genuine forks
When a decision is genuinely the user's to make and you can't resolve it from the
task, the code, or a sensible default — ask, batched, not one at a time. Don't
manufacture a default for a load-bearing, ambiguous choice.

### 7. Persist progress to durable memory
For work spanning multiple steps or sessions, keep a running log on disk (a plan /
progress file): what's done, the decisions + their receipts, what's next, and
anything that drifted. Re-read it when you resume. The conversation is not durable
memory; the file is.

### 8. Surface gaps honestly
Name what you did NOT do, what you could not verify (and what a cheap proxy didn't
cover), and what's out of scope. "Known-untestable" and "out-of-scope" sections
are features, not omissions. Reporting a failure faithfully beats a confident
wrong "done".

## Domain patterns

- **Software:** read the relevant code before writing; trace the call sites you'll
  affect; plan the diff; write or run the test/command and *observe* behavior —
  don't infer it from the diff; reuse existing helpers before writing new ones.
- **Research:** gather sources before synthesizing; every claim cites evidence;
  mark inference vs. fact; verify the load-bearing claims, not just the easy ones.
- **Data:** understand the data's shape and quality before computing; state the
  hypothesis before running the numbers; sanity-check results against a known case.
- **Long-running:** define done up front; keep the work log (§7); re-read it on
  resume; checkpoint after each meaningful unit.

## Stopping condition
Stop when §1's done-criteria are met **and** every weakness named in §5 is either
fixed or explicitly flagged with a reason it's acceptable to ship — not before,
and not endlessly hunting a flawless state that doesn't exist.
