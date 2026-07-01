---
name: tale-mode
version: 1.0.0
description: >-
  Make Claude work rigorously on complex or high-stakes tasks instead of
  one-shotting them. Triggers: "tale mode", "tale on" — or
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
> that can spawn sub-agents (Claude Code and OpenAI Codex both can). On hosts that
> can't (e.g. the claude.ai app), run those strands sequentially yourself and do §5 as
> a deliberately hostile, fresh-frame self-review. Everything else applies as-is.

> **Phase pipeline (per host).** For a large, multi-phase feature, drive it through the
> pipeline instead of one long session — it writes an approved plan decomposed into
> independently-shippable phases, then builds one phase per fresh session (enter plan
> mode, re-verify the plan against current code, wait for approval before editing).
> **Claude Code:** the slash commands `/tale-mode:plan-phase <feature>` then
> `/tale-mode:kickoff-phase <plan-file> <phase>`. **Codex** (no user slash commands —
> skills are the trigger): the same two workflows ship as the `plan-phase` /
> `kickoff-phase` skills — invoke them from the `/skills` picker and name the
> plan-file + phase in your prompt. `/clear` (CC) or a fresh session (Codex) between
> phases keeps context lean. Mention this for big multi-step work; skip it for
> single-session tasks.

> **Verification gate (per host).** The §4 "run it and observe" and §5 review steps map
> to different tools per runtime — run the equivalent, never skip it.
> **Claude Code:** §4 = `/verify` (did the change behave?) + `/run` (boot/drive the live
> app), picking what fits (pure logic → `/verify` against a test; UI/API → `/run` + a real
> browser/curl pass); §5 = `/code-review` on the diff (pass `<base>...<branch>`, no PR
> needed) and, for auth / money / secrets / storage, `/security-review` — both are bundled,
> model-invocable skills, invoked via the Skill tool.
> **Codex:** §4 = run the test / drive the app yourself and observe (there is no `/verify`
> or `/run` skill); §5 routine = a **free fresh-context sub-agent** review (Codex can spawn
> one — frame it hostile), plus the bundled **`codex-security`** skills for auth / money /
> secrets / storage.
> **Both hosts:** a *cross-model metered* reviewer — Greptile, or the **CodeRabbit**
> `code-review` skill on Codex — is the strongest §5 pass but is **owner-triggered: never
> auto-run, comment `@…`, or push-loop it (each trigger costs real money).** Surface it; let
> the owner spend it. The fresh-eyes `plan-reviewer` complements the gate, never substitutes.
> Actually run the gate. A behavioral check that *can't* run yet (blocked on external
> provisioning — services, creds, infra) is a §0 deferral: log it in durable memory and treat
> the work as not-done until discharged, never skip it silently.

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
it's written to durable memory (§7, e.g. the committed `.claude/deferrals.json`) as a
named, owned item: a gap you merely say
out loud (§8) dies on session reset — the next run starts clean and never sees it.
Test before deferring: *if this session ended now, would this still get picked up?*
If no — do it now, or write it into the plan first. (Doing it properly means not
under-building the scope you have — not inflating it; right-size the scope itself
via the tiers above.)

## The loop

### 1. Map the work before acting
Write the plan first. Number the stages; for each, state the **expected output**
and how you'll know it's right. Define **done** up front — the concrete condition
that lets you stop. A plan you can't check against isn't a plan. **Split each "done" claim by
how it's judged:** *testable* → a deterministic command (the arbiter, §4); *un-testable* → a §5
review. Don't dress an un-testable claim as a passing test.

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

**This fan-out IS your workflow.** The Explore agents that map the code (§1), the
adversarial `plan-reviewer`, the `/code-review` finder fan-out, and the §5 fresh-eyes
reviewer are a hand-built version of what Claude Code's dynamic workflows / ultracode
mode automate — independent agents cross-checking each other. The breadth and the
caught bugs come from *this orchestration*, not from a higher per-agent effort dial:
once a verified plan and this fan-out are in place, the effort setting is mostly
mechanical (cranking it buys cost, not quality). Spend the budget on the orchestration
and an independent review — not the dial.

**When to reach for ultracode / a Workflow:** only a genuine *breadth* task — a codebase
audit, a large migration or sweep, multi-angle research — where the win is coverage, not
depth, and the fan-out can't be done by hand. On a coherent single build it's
double-orchestration (this fan-out already covers it). The model can't set ultracode
itself, so when you spot a real breadth task, **tell the user to switch** (`/effort` →
ultracode) rather than grinding it single-threaded.

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

**Diagnosis — when a check fails or something's broken.** Reactive guessing is the
costliest failure mode here. Work foundation-first:
- **Verify the foundation before the symptoms.** Before asking *why* it's broken,
  confirm the thing *exists* and the environment is *capable* of it at all — one
  existence/capability check often collapses the whole search. (Changing the config,
  then the URL, then the network path is wasted if the thing you're operating on never
  existed.)
- **Two-strike rule.** If two fixes in a row don't work, STOP — that's the alarm that
  you're debugging downstream of a false assumption. Re-verify the foundational fact
  before a third attempt; treat each hypothesis as a claim to verify, not a fact.
- **Respect documented constraints.** When a plan/doc flags something deferred /
  blocked / environment-specific, confirm it's even possible *here* before forcing it.
- **Drive it yourself.** Run the diagnostics and fixes with the tooling you have; hand
  the user a command only when it genuinely needs them (a secret you don't hold, a
  foreground process's live output, an interactive login, an outward-facing action) —
  each "you run it, paste it" round-trip is ~10× slower.
- **Stuck? Get a fresh frame** — hand the full state to a clean-context agent (or a
  different model) framed as a skeptic; it won't share your anchor (the §5 lever,
  applied to diagnosis).
- **Persist, and surface `/goal`.** Keep looping (check → hypothesize → test → fix) to
  a verifiable success before declaring done. You **cannot** start `/goal` yourself —
  it's a user command — so when a debug is worth an enforced loop, say so.

### 5. Critique before delivering — escalate for high-stakes
- **Always:** read your output as a skeptical reviewer and name the **most
  consequential** weakness you can find, ranked by impact. A cosmetic nit does not
  discharge this step — producing only trivial weaknesses is itself a signal the
  real review hasn't happened. Fix it, or flag it with a reason it's acceptable to
  ship. Never present as if flawless. But if, after a genuine pass, the only real
  weaknesses are minor, say so plainly — don't manufacture severity to satisfy this
  step.
- **High-stakes — review with FRESH EYES, not harder eyes.** Self-review has a hard
  ceiling: a model fixes an error instantly when it's framed as *someone else's*
  code, yet misses the *same* errors in its own output — a self-correction
  *activation* failure, not a knowledge gap. More effort can't close it (you can't see your own frame), and **re-reading in the
  same context doesn't either — only a fresh context does.** So spawn a **separate
  sub-agent with a clean context**, hand it ONLY the diff + the spec + the checklist
  below, and frame it hostile: *"you're a jaded senior reviewing a rushed junior's PR
  — assume it's wrong until proven right; hunt what breaks out-of-session."* The fresh, adversarial frame is the unlock — a
  clean-context pass beats re-reading in the same context. **Order your verdict by *independence* — the validator that least
  shares your blind spots wins.** (1) **The arbiter of "done" is §4's deterministic gates** —
  a real test/command exits 0 or it doesn't; zero model bias, nothing to fool. (2) **The
  strongest *review* is a different model** (different training → different blind spots; e.g.
  Greptile / GLM on the PR catches the class of bug your own passes *structurally* share —
  empirically, a real session's own `/code-review` + self-critique + same-model `plan-reviewer`
  all missed a bug that cross-model Greptile caught; **metered bots are owner-triggered — surface
  the option, never auto-run or push-loop them**). (3) **A fresh-context *same-model* pass** (a
  sub-agent / the `plan-reviewer` agent, or `/clear`) breaks your *context* anchor but still
  shares your *model's* blind spots — so it's the **anchoring-breaker and always-available floor,
  never the final arbiter.** Use it to surface candidates; let the deterministic gate and the
  different-model pass *settle* them.
- **Run the blind-spot checklist mechanically** — these are "correct in-session,
  wrong out-of-session" misses that are invisible to reasoning, so check them as a
  list, never by thinking harder:
  1. **Sibling parity** — diff every near-identical function pair for asymmetry in
     try/catch, timeout, disabled/in-flight state, or cleanup (one twin handled it,
     the other didn't — the handled twin makes the gap read as "done").
  2. **Temporal coupling** — every client-cached credential/URL records its issuer
     TTL and refreshes before expiry; every loader/SSR fetch has an `AbortController`
     (+ `clearTimeout`). Green in a 5-min test ≠ alive at 1 hour.
  3. **Cleanup completeness** — every timer / listener / subscription / fetch has a
     matching teardown; enumerate ALL refs, not just the obvious one.
  4. **Credential hardening** — credential-bearing cookies set Secure + SameSite
     (+ HttpOnly / `__Host-` where the JS doesn't need to read them).
  5. **Backend-contract reconciliation** — the client handles every documented return
     value, incl. partial-success / zero-count, before committing optimistic UI.
  6. **Edge-state render** — guard primary==fallback (i18n); walk each locale's
     offline / error / empty states, not just the happy English path.
  7. **Prop/param liveness** — every declared prop/param/field is actually read;
     delete or wire the orphans.
  8. **Batch the bounded-N loop** — per-row queries inside a loop → a single `IN (...)`.
  9. **Render purity** — no DOM reads / impure calls (`matchMedia`, `window`,
     `Date.now`, `Math.random`) in a render body (SSR/hydration safety).
  10. **No RegExp from external input** — parse literally (split/indexOf); flag any
      guard whose safety leans on a non-local invariant staying true.
  11. **Error-feedback** — every awaited mutation has a `catch` that shows the USER a
      *distinct* failure message (not swallowed, not the prompt/instruction string).
- **Loop until a fresh pass is clean — gate on the REVIEW, not the tests.** A fix can
  introduce a new defect, and green tests are not a review of the fix delta. So:
  fresh-eyes review + checklist → fix every P0/P1 → **re-review the post-fix delta in
  a new fresh frame** → repeat until a fresh pass surfaces no P0/P1. Cap it: gains
  saturate after 1–2 rounds and an unanchored loop can *degrade* good work — stop on
  a clean fresh pass or a hard round-cap, never loop forever. Fold every finding back in, numbered, so it's traceable. **Hold this loop yourself** —
  keep re-reviewing until a fresh pass is clean before declaring done. You can't start
  `/goal` (it's a user command); when a gate is worth an enforced backstop, surface it —
  the *user* wraps the session in `/goal <zero-P0/P1 condition>` and a separate evaluator
  re-runs you until it holds (the worker can't grade its own homework).

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

**Deferrals get a committed, reviewable home — `.claude/deferrals.json`.** A deferral
kept only in a scratch note dies unreviewed; record each as a *committed*, structured
entry so it surfaces in the PR diff where a reviewer actually sees it:
`{ "deferrals": [ { "id", "what", "why", "owner", "created", "status" } ] }`
(`status ∈ {open, discharged}`; *discharge* = promote it back to active work). This is the
structured, PR-visible companion to the narrative progress file above — not a second source
of truth. It is a **convention, not an enforced gate**: no hook reads it (a shell check
can't decide "is this scope item built?"), so no-silent-drops stays *your* discipline
(here and §8) — write the deferral, or it didn't happen.

### 8. Surface gaps honestly
Name what you did NOT do, what you could not verify (and what a cheap proxy didn't
cover), and what's out of scope. "Known-untestable" and "out-of-scope" sections
are features, not omissions. Reporting a failure faithfully beats a confident
wrong "done". **Any gap that must actually get fixed graduates to durable memory
(§7), not just this report — a gap that lives only in the conversation is lost the
moment the session resets.**

## Autonomous goal loop — "keep going until it's actually done"
The disciplines above are *how* to work; this lets you **keep working without the user
re-prompting every step.** Claude Code's `/goal` and `/loop` are user-only — you can't type
them. This is the loop you *can* start yourself: **arm a goal-file that a Stop hook enforces.**
**These are *separate systems* — don't conflate them:** `/goal` is a built-in that judges a
natural-language condition with a *model reading the transcript*; the goal-file here runs a
*deterministic shell `check`*. Running `/goal` does **not** arm this goal-file or the L2 governor,
and this loop does not depend on `/goal`.

**Setup:** none — the Stop hook ships *inside* the tale-mode Claude Code plugin and is registered
automatically on install (default-on). For loops longer than ~8 rounds, raise
`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` in `~/.claude/settings.json` (the loop is safe without it —
`max_rounds` + a fail-open are self-contained). Proven: 161 checks across 56 cases
(fail/pass/pause/edge/log + committed-config + cross-platform cwd-root + pending-marker adoption
+ no-progress + multi-line gates) in `tests/test-stop-goal-loop.sh`.

**Arm a goal** — write `<project>/.claude/active-goal.json` when you start a hard,
*observably-verifiable* task:
```json
{ "goal": "the auth E2E prints PASSED",
  "check": "npm test -- auth 2>&1 | grep -q PASSED",
  "rounds": 0, "max_rounds": 25, "needs_user": null }
```
- `check` is a **deterministic** shell command — exit 0 means done. It's the gate (a real
  command, stronger than a model reading the chat). Pick one that **can't pass on a band-aid**
  (a real test/E2E, never `echo PASSED`). **Judge-to-claim:** put every *testable* "done" claim
  in `check` — it's the arbiter. For a genuinely *un-testable* condition ("the review found no
  P0/P1"), do NOT fake it into a shell check that can pass on a band-aid — route it to a §5
  cross-model / fresh-eyes review (or, to enforce it, the *user* wraps the session in `/goal`,
  which model-judges the transcript).
- From then on, each time you'd end the turn the hook runs `check`. Fails → you get another
  turn, with the foundation-first + two-strike disciplines injected as the reason. Passes →
  the file clears and the turn ends. You literally cannot stop until it's true.

**Pause for the user** (a secret you can't hold, a dashboard only they see, a login, an
outward-facing action): set `needs_user` to a one-line ask in the goal-file, then ask. The hook
lets the turn end so they can answer; clear `needs_user` (→ `null`) next turn to resume.

**Stop / give up:** ends when `check` passes, at `max_rounds`, or — if the goal proves genuinely
unreachable — when you **delete the goal-file and explain why.** Never weaken the `check` to
force a pass; that band-aid is the exact thing this system exists to prevent.

**Arm it for** observable goals (a debug — "the repro passes"; a feature — "the test is green";
a phase). Not pure-judgment goals (no deterministic check → nothing to gate on).

**Layer 2 (the adversarial governor — optional companion plugin):** a `type:"agent"` Stop hook —
a FRESH-CONTEXT, **read-only** reviewer (Read/Grep/Glob) pinned to Sonnet that, once you're stuck
(`rounds` ≥ 2), reads the goal/plan/code with a skeptic's frame and names the unverified *foundation*,
a violated *documented constraint*, or a *band-aid* — the failures Layer 1 can't see. It breaks the
anchor (verified to fire in `-p`). It ships as the **separate `tale-mode-governor` plugin** (it makes a
per-turn model call, so it's opt-in): `/plugin install tale-mode-governor@tale-mode` to add it.

**Live-test the runtime** (the script proves the hook's logic; only a live session proves Claude
Code re-runs the turn on a block): arm `{"goal":"marker","check":"test -f /tmp/tale-done","rounds":0,"max_rounds":5}`,
end your turn and watch it iterate; `touch /tmp/tale-done`, confirm the next turn-end clears + stops.

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
