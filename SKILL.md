---
name: tale-mode
description: >-
  Make Claude work rigorously on complex or high-stakes tasks instead of
  one-shotting them. Triggers: "tale mode", "tale on", "go deep" — or
  self-activates on hard multi-step work. Enforces
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

> **Claude Code commands.** For a large, multi-phase feature, drive it through the
> pipeline instead of one long session: `/plan-phase <feature>` writes an approved
> plan decomposed into independently-shippable phases, then `/kickoff-phase
> <plan-file> <phase>` builds one phase per fresh session (it enters plan mode,
> re-verifies the plan against current code, and waits for approval before editing).
> `/clear` between phases keeps each session's context lean. Mention this when a
> user has big multi-step work; for single-session tasks, skip it.

> **Claude Code verification gate.** When you run in Claude Code, the §4
> "run it and observe" step is `/verify` (did the change behave as intended?) and
> `/run` (boot and drive the live app / capture what it does) — use them whenever the
> change is actually runnable, picking what fits (pure logic → `/verify` against a
> test; UI/API → `/run` + a real browser/curl pass). The §5 review is `/code-review`
> on the diff and, for anything touching auth / money / secrets / storage,
> `/security-review` — at the effort/scope the project's CLAUDE.md sets. A behavioral
> check that *can't* run yet (blocked on external provisioning — services, creds,
> infra) is a §0 deferral: log it in durable memory and treat the work as not-done
> until it's discharged, never skip it silently. On hosts without these commands, do
> the equivalent by hand.

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

**Split into phases when the work won't fit one session.** Independently of the
tier above: if executing the task end-to-end would touch more than one coherent
verify-loop, or bloat the working context toward the compaction threshold (~150K
tokens — not the 1M hard limit; by 1M you've long since lost recall to context-rot
and are re-reading the whole window every turn, which on a subscription burns your
usage allowance fastest), plan it as multiple phases and run one per session with a
`/clear` between. Blast radius sets the review depth; "fits one session" sets the
phase boundaries.

**Phase the rollout, not the rigor.** Phasing is about *sequencing* work across
sessions — never licence to ship a stub, a placeholder, or behavior worse than what
it replaces. Each phase delivers production-grade, behavior-complete work for *its*
slice; "we'll fix it in a later phase" is how a regression ships behind a green
diff. If a slice can't be done properly yet, shrink the slice — don't lower the bar.

**Do it now, or defer it in writing — never only in your head.** Default to the
proper implementation now. A v1 / MVP / stub is justified only when the full
version genuinely *can't* be built yet — a missing prerequisite, a separate
high-stakes surface that deserves its own review (e.g. a money path), or it won't
fit the session — never just because it's faster. And a deferral only counts once
it's written to durable memory (§7) as a named, owned item: a gap you merely say
out loud (§8) dies on session reset — the next run starts clean and never sees it.
Test before deferring: *if this session ended now, would this still get picked up?*
If no — do it now, or write it into the plan first. (Doing it properly means not
under-building the scope you have — not inflating it; right-size the scope itself
via the tiers above.)

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

Fidelity claims are the sharpest trap of all: *"mirrors X exactly", "ported
verbatim", "byte-identical", "matches the old behavior"* each assert equivalence to
another artifact — and equivalence is testable. Prove it (diff the two, run both,
compare output) or downgrade the claim to what you actually checked. Never inscribe
"mirrors exactly" as a comment you did not diff.

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
- **Sweep beyond the diff.** A change to config, a build step, a dependency, or a
  shared interface can break files the diff never touches. Enumerate the consumers
  of what you changed — other call sites, scripts, generated artifacts, CI/guard
  scripts — and re-run them. Diff-scoped review is structurally blind here; only
  running the dependents catches it.
- **Run the project's own gates — inventory them mechanically, not from memory.**
  `grep` the `scripts` block of every `package.json`, list `tools/` + `scripts/`,
  read the CI workflow — *then* run every gate this change could touch and paste the
  exit codes. Re-running the subset you happen to remember is exactly how a
  silently-broken gate survives: one an uninstalled dep makes un-runnable, or a
  moved build-output path makes always-fail, looks "fine" only because you never
  invoked it. A gate you *added* but never ran is not done; a gate that *silently
  always fails* is worse than none.
- **When full verification is prohibitively expensive** (a 40-min suite, a
  prod-only behavior, a destructive command): verify the cheapest *sufficient
  proxy* and state, in §8, exactly what the proxy does not cover.
- **Keep the main thread lean.** For heavy verification (a browser run, a large
  command dump), drive it from a sub-agent (§3) that reports pass/fail + the
  citations — don't park raw logs or snapshots in your working context.

**Internal consistency is not correctness. A clean diff is not evidence it
works — run it and observe the behavior.**

### 5. Critique before delivering — escalate for high-stakes
- **Always:** read your output as a skeptical reviewer and name the **most
  consequential** weakness you can find, ranked by impact. A cosmetic nit does not
  discharge this step — producing only trivial weaknesses is itself a signal the
  real review hasn't happened. Fix it, or flag it with a reason it's acceptable to
  ship. Never present as if flawless. But if, after a genuine pass, the only real
  weaknesses are minor, say so plainly — don't manufacture severity to satisfy this
  step.
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
progress file): what's done, the decisions + their receipts, what's next, **every
deferred item (§0) and open gap (§8)**, and anything that drifted. Re-read it when
you resume — and reconcile the deferral list, confirming nothing silently fell
through. The conversation is not durable memory; the file is.

### 8. Surface gaps honestly
Name what you did NOT do, what you could not verify (and what a cheap proxy didn't
cover), and what's out of scope. "Known-untestable" and "out-of-scope" sections
are features, not omissions. Reporting a failure faithfully beats a confident
wrong "done". **Any gap that must actually get fixed graduates to durable memory
(§7), not just this report — a gap that lives only in the conversation is lost the
moment the session resets.**

## Worked example (Substantial tier)
A filled-in pass, so the artifacts above have a shape to copy. Task:
*"Add a 5-req/min rate limit to POST /api/signup."*

**§1 Map** — *done = limit enforced and a test proves the 6th request in a window
gets 429:*
1. Find the signup handler + how requests are keyed → *expect:* file + signature.
2. Wire a limiter before the handler; pick store + window → *expect:* it's in the chain.
3. Test 5 pass / 6th blocked → *expect:* green test, observed `429`.

**§2 Receipts**

| Decision | Source |
|---|---|
| 5 req / 60s | user: "5-req/min" |
| Key by IP, not user id | my judgment — signup is pre-auth, no user id exists yet |
| Reuse `kv` client, no new dep | reuse — `src/lib/kv.ts:12` already exports a TTL client |

**§4 Verify (ground truth):** re-read `routes/signup.ts:1-40` — handler is `POST` at
line 8, no existing limiter (*confirmed, not assumed*). Ran the test: the 6th request
returned `429` (*observed, not inferred from the diff*).

**§5 Critique:** most consequential weakness — IP keying means a NAT'd office shares
one bucket (false positives). Acceptable to ship: abuse is the bigger risk and the
limit is generous; flagged for follow-up. *(The real one, not a manufactured nit.)*

**§8 Gaps:** not load-tested under concurrency; the KV TTL race (two simultaneous
5th requests) is unverified — low-impact at this limit.

## Domain patterns

- **Software:** read the relevant code before writing; trace the call sites you'll
  affect; plan the diff; write or run the test/command and *observe* behavior —
  don't infer it from the diff; reuse existing helpers before writing new ones.
  When you port or replace existing behavior, run a **parity check** against the
  original — and check the **full observable contract** (status + *every* response
  header + body), captured by RUNNING both and diffing, not by eyeballing the two
  handlers' source. Middleware, wrappers, and framework layers inject behavior the
  handler source never shows (a privacy header stamped upstream, a default 404/500,
  an auto-served HEAD) — a handler-to-handler read is structurally blind to them.
  Anchor on the TRUE original, never a prior refactor step that may itself have
  drifted. The new version must be equivalent-or-better; any deliberate divergence
  is called out with rationale, not hidden. Confirm version-specific
  behavior against current docs, not training memory — adapter conventions,
  build-output layout, and breaking changes are top sources of "looked right,
  didn't run".
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
