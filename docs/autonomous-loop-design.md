# Tale-Mode — Autonomous Foundation-First Loop (design spec)

> **Status:** DESIGN — hash out §8, then build §9. Captured 2026-06-24 before a context reset.
> **Home:** the tale-mode skill / repo (github.com/alicicek/tale-mode). **Everything here stays GENERAL** —
> no project specifics; the only project-supplied input is a `check` command. Build it in a FRESH session
> with this file as the spec (`/tale-mode:kickoff-phase` this doc).
>
> **One-line goal:** make tale-mode keep going *autonomously and intelligently* until a verifiable goal is
> met — driving its own diagnostics/fixes, refusing to circle or band-aid, pausing only for what genuinely
> needs the human — i.e. the realistic version of "Fable just keeps going," within what the platform allows.

---

## BUILD STATUS (2026-06-24) — Layer 1 hardened + tested; Layer 2 rebuilt; live-test gating
**Layer 1 (deterministic command hook)** is built, hardened, tested: `hooks/stop-goal-loop.sh`
(120/120 in `tests/test-stop-goal-loop.sh`). An adversarial ultracode audit found + fixed: a **P0
infinite-loop trap** (now FAILS OPEN if it can't persist the round counter), a whitespace-check
false-pass, a wrong-project `cwd` fallback (now REQUIRES `CLAUDE_PROJECT_DIR`), and a missing check
timeout. Corrections to stale prose elsewhere in this doc:
- **Block contract:** Stop blocks via `exit 0` + top-level `{"decision":"block","reason":"…"}`
  (command AND agent hooks). `exit 2` + stderr also blocks but is NOT what we use. The steer is
  `reason`, **not** `additionalContext`. (§2 / §4.2 / §57 / §208 prose saying exit-2/additionalContext is stale.)
- **Block cap:** `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` (default 8, raisable) IS documented — in the hooks
  *guide* (an earlier "not in the docs" was a guide-vs-reference page mismatch). We still do NOT rely
  on it; the self-contained safety is `max_rounds` + the fail-open. Belt, not the only belt.
- **Layer 2 — SUPERSEDED in governor v2.0.0 (2026-07-02).** Everything below about a
  `type:"agent"` Sonnet hook that *blocks* describes v1, kept as build-log history. The shipped
  governor is now ONE `type:"command"` hook (`governor.sh`) on both hosts: a free bash gate that
  spawns a single read-only reviewer (`claude -p` on Claude Code / sandboxed `codex exec` on
  Codex) exactly when a goal first fails twice, and returns an ADVISORY message — it no longer
  blocks; Layer 1 owns the decision.
- **Layer 2 (the `type:"agent"` governor): VERIFIED it FIRES in headless `-p`.** An earlier "never
  fires" was a broken-INSTRUMENT error — agent hooks are **READ-ONLY** (Read/Grep/Glob; NO Bash/Write),
  so a write-based detector found nothing; a valid block-decision test showed it firing + re-turning to
  the cap. At two-strike it READS the goal/plan/code with a skeptic's frame and blocks with a concrete
  steer that reaches the agent. Its prompt reasons from reads only (Grep the plan, Read the code) — no
  shell, no `git diff`. Operationalizes the §3/§5 fan-out.
- **`needs_user` pause** added + tested.

**Live-verified end to end (`claude -p`):** Claude Code DOES re-run the turn on `{decision:block}` —
block→re-turn, **multi-round** iteration, `max_rounds` give-up, the model **self-arming** a goal, and
the `needs_user` pause were all observed in live sessions. **Honest caveat:** capable models (Opus AND
Haiku) self-regulate — foundation-first, no band-aid, bail correctly — so Layer 2's anchor-breaking
*value* is insurance for the rare real stall (un-stageable in a sandbox); its *mechanism* is proven.

> **Reading note.** Everything above (BUILD STATUS) is **what shipped**. The numbered sections below
> are the **original design**, kept as an honest build log. Where they differ, BUILD STATUS wins:
> Layer 2 shipped as a **read-only `type:"agent"` hook** (Read/Grep/Glob) — *not* the
> transcript-reading Haiku shell-analyzer the body sketches — and the goal-file is the **5 fields**
> the hook actually reads (`goal`/`check`/`rounds`/`max_rounds`/`needs_user`); the `started`/`notes`
> fields below were planned for that analyzer and never shipped.

## 1. The problem (why this exists)
Observed over a long real session (debugging a media pipeline, ~30 user round-trips):
- **Reactive, layer-by-layer guessing.** Chased symptoms (secret → URL → tunnel) one plausible hypothesis at
  a time, *downstream of an unverified assumption* ("the artifact exists"). One foundational check would have
  collapsed it in minutes.
- **Ignored a documented constraint.** The plan literally said the operation was deploy-only; the model spent
  hours forcing it locally.
- **Narrated commands instead of running them.** Many "you run it, paste it" round-trips the model could have
  driven itself (~10× slower each).
- **Risk of band-aids.** Reactive loops tend toward loophole/temp fixes that don't touch the real root or
  architecture.
- **No autonomy.** The human had to re-prompt every single step.

The fix is **not** "try harder" (the disciplines already existed in CLAUDE.md and still drifted). It's
**structure**: an autonomous loop, governed by an LLM that watches the *process*, running disciplines that
actually fire.

## 2. Hard platform constraints (verified, 2026-06)
These shape the whole design — do not design against them:
- **The model cannot invoke slash commands** (`/goal`, `/loop`, etc.). They are user-only. So the loop **cannot
  be started by the model typing `/goal`.**
- **`/goal` is real** (a user-typed completion loop; a Haiku evaluator judges the *conversation* each turn and
  auto-continues until the condition holds) — but user-only, and it can't run commands, only read the chat.
- **`/loop` is real** (user-started; the model self-paces iterations via scheduled wake-ups) — also user-started.
- **The only model-reachable "keep going" levers are:**
  1. **Stop hooks** — a `Stop` hook returning **exit 2 blocks the turn from ending** and feeds `additionalContext`
     back; the model then takes another turn. Bounded by a **consecutive-block cap** (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`,
     default 8, raisable). The model **can arm/trigger this indirectly** by leaving a marker the hook reads.
  2. **Files the model writes** + a hook that reads them.
- **Hooks can inject** `additionalContext` (≤~10KB, becomes a system-reminder the model sees) and `systemMessage`
  (shown to the user); they **cannot** invoke slash commands.

**Consequence:** the loop is built from **a model-armed goal-file + a Stop hook**, not from `/goal`.

## 3. Architecture — three layers

### Layer 1 — Self-armed goal loop (the autonomy)
- The model **arms a goal** by writing a goal-file (the success condition + a **deterministic check command**).
  This is how the model "starts a `/goal`" without being able to type one.
- A **Stop hook** refuses to let the turn end while a goal-file exists and its check hasn't passed → the model
  keeps getting turns.
- This is *stronger* than `/goal`: the gate is a **real command** (a test, a grep, an E2E harness exit code),
  not a Haiku reading the chat.

### Layer 2 — LLM session-analyzer (the intelligence / "is it messed up?")
The novel part, and the user's key ask: **a small LLM (Haiku, or stronger when needed) reads the recent
session each turn and judges the *process*, not just the condition.** "Like `/goal`, but it reads the
transcript and steers." On each Stop it returns a verdict + specific guidance:
- **Met?** Is the goal *genuinely* satisfied, or faked/short-circuited? (Cross-checks the deterministic result
  against what the agent actually did — catches a green check reached via a band-aid.)
- **Circling?** Repeated near-identical attempts with no new information → "you're spinning; stop and verify the
  foundation."
- **Foundation verified?** Did the agent confirm the artifact *exists* / the environment is *capable* before
  fixing symptoms? If not → "check existence/capability first."
- **Band-aid risk?** Is the latest fix a loophole/temp hack that dodges the root or the architecture? → "this is
  a patch, not a fix — is the design right?"
- **Needs the human?** Does the next step genuinely require the user (a dashboard only they see, a secret/token
  the agent doesn't hold, an interactive login, an outward-facing/destructive action)? → pause + surface one
  clear ask.

The analyzer is the **real governor** — it decides *continue / done / pause-for-user / give-up-and-explain* —
replacing the dumb numeric cap with an *intelligent* stop. This is what prevents the "circle 10×" and the
"band-aid without checking foundations" failure modes.

### Layer 3 — Disciplines (the behavior each round)
Already shipped in tale-mode §4 (Diagnosis) + global CLAUDE.md; the loop runs them every round:
- **Foundation-first** — verify existence/capability before symptoms.
- **Two-strike rule** — two failed fixes ⇒ stop, re-verify the foundational assumption.
- **Drive-it-yourself** — run diagnostics/fixes; only hand the human what genuinely needs them.
- **Respect documented constraints** — deferred/blocked/env-only is a hard wall; confirm feasibility before forcing.
- **Fresh frame when stuck** — hand the state to a clean-context agent / different model (it won't share the anchor).

## 4. Mechanics (concrete)

### 4.1 The goal-file — `.claude/active-goal.json`
Written by the model (via tale-mode/kickoff) when starting a hard, verifiable task:
```jsonc
{
  "goal": "human-readable success condition",      // e.g. "the auth E2E prints PASSED"
  "check": "shell command; exit 0 == goal met",    // DETERMINISTIC. e.g. "npm test -- auth | grep -q PASS"
  "rounds": 0,                                        // incremented by the hook
  "max_rounds": 25,                                   // hard ceiling; the loop gives up here
  "needs_user": null                                  // set by the hook when paused for a human dep
}
// NOTE: the originally-planned "started" + "notes" fields did NOT ship — the loop reads only these 5.
```
The model **clears the file** (or the hook does) when the goal is met or judged unreachable.

### 4.2 The Stop hook (`stop-goal-loop.sh`) — pseudo-logic
```
on Stop:
  goal = read .claude/active-goal.json  ;  if none -> exit 0   # normal turns untouched
  if goal.rounds >= goal.max_rounds -> exit 0 + systemMessage "goal loop hit max_rounds; stopping" ; clear
  pass = run goal.check  (capture output, exit code)
  verdict = ANALYZER(transcript_tail, goal, pass, check_output)   # Layer 2 — Haiku call
  increment goal.rounds ; append verdict.summary to goal.notes
  case verdict.decision:
    DONE        (pass && analyzer agrees genuine) -> exit 0 ; clear file
    NEEDS_USER  -> exit 0 ; set goal.needs_user=verdict.ask ; systemMessage(verdict.ask)   # pause for human
    GIVE_UP     (unreachable / circling-exhausted) -> exit 0 ; clear ; systemMessage(verdict.why)
    CONTINUE    -> exit 2 ; additionalContext = verdict.guidance   # keep going, steered
```
- Stop-hook input gives the **transcript path** + `stop_hook_active`. Do **not** early-exit on
  `stop_hook_active` (we *want* the loop); the numeric cap + `max_rounds` + the analyzer's GIVE_UP are the safeties.

### 4.3 The analyzer (Layer 2) — a Haiku call from the hook
- **Input:** the last N turns of the transcript (from the transcript path) + the goal + the check's exit/output.
- **Prompt (sketch):** "You are auditing an autonomous coding agent's loop. Goal: <goal>. Deterministic check:
  <pass/output>. Recent transcript: <tail>. Decide: is the goal *genuinely* met (not faked/band-aided)? Is the
  agent circling (repeating attempts)? Did it verify the foundation (existence/capability) before fixing symptoms?
  Is the latest fix a loophole/temp-hack dodging the root or architecture? Does the next step need the human (a
  dashboard, a secret, a login, an outward-facing action)? Return JSON: {decision: DONE|CONTINUE|NEEDS_USER|GIVE_UP,
  guidance, ask, why, confidence}."
- **Output → the hook's feedback.** Keep guidance concrete ("verify X exists before another fix"; "you've tried
  3 variants of the same fix — step back").
- **Model:** Haiku by default (cheap, runs every turn). Escalate to a stronger model for high-stakes/low-confidence
  (open question §8).

### 4.4 The cap
- **Lift `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`** well above 8 (e.g. 30+, or effectively off) — the analyzer is the
  *intelligent* governor, so the numeric cap is just a final backstop. `max_rounds` in the goal-file is the
  per-goal hard ceiling.

### 4.5 The human-dep pause (the "no more pointless round-trips" win)
- The analyzer flags `NEEDS_USER` only for things genuinely requiring the human: a dashboard only they can see,
  a secret/token the agent can't hold, an interactive login, an outward-facing/destructive action.
- On pause: the loop stops cleanly with **one clear, specific ask** (what to do, why), and resumes when the
  user replies. Everything else (running CLIs, reading local state, querying DBs) the agent does itself.

## 5. How it should FEEL — debugging walkthrough
1. Model arms: `active-goal` = {goal:"video E2E prints PASSED", check:"node e2e.mjs | grep -q PASSED"}.
2. Turn ends → hook: check fails → analyzer: "no evidence the artifact exists; you've made 0 existence checks →
   CONTINUE, guidance: verify it exists before any fix."
3. Model checks existence → finds it's absent (the real root) → fixes the actual cause.
4. Turn ends → check passes → analyzer: "genuinely met, not a band-aid → DONE." Loop clears. Done.
   *(Contrast: the real session took ~30 human round-trips to reach the same place.)*

## 6. Use-case coverage (must work for all three)
- **Simple feature:** goal = "feature works + its test passes." One short loop; analyzer rarely intervenes.
- **Multi-phase feature / refactor:** each phase is its own armed goal (build → verify → next); the analyzer
  catches regressions and band-aids between phases; pauses only for genuine forks. Pairs with `/tale-mode:kickoff-phase`.
- **Debugging:** the headline case. Foundation-first + two-strike + the analyzer's circling/band-aid detection
  are exactly what kills the "spin 10×" and "temp-fix without checking architecture" failure modes.

## 7. Honest caveats / risks (validate at build time)
- **Deterministic check required.** Works for *observable* goals (test passes, file exists, E2E PASSED). For a
  pure-judgment goal, the deterministic gate degrades to the analyzer alone (weaker; flag it).
- **Analyzer can mis-judge** (it's an LLM). Mitigations: it only *steers*/stops, never silently edits; its notes
  are appended to the goal-file (auditable); low-confidence ⇒ escalate model or pause for the human.
- **Transcript privacy.** The analyzer reads the transcript tail. Keep the call on the user's own
  account/model; never ship transcript to a third party. Redact obvious secret shapes before the call.
- **Runaway.** Bounded three ways: `max_rounds`, the (lifted) numeric cap as a final backstop, and the analyzer's
  GIVE_UP. Loop must always be escapable by clearing the goal-file.
- **The model must ARM the loop** (write the goal-file) — so tale-mode/kickoff has to do that reliably; if it
  forgets to arm, there's no loop (acceptable: degrade to normal behavior).
- **Not fully hands-off** — by design it pauses for genuine human deps. That's correct, not a bug.

## 8. Open questions to hash out (before building)
1. **Analyzer model:** Haiku always? Escalate to Sonnet on low confidence or high-stakes? Cost vs quality.
2. **Where the analyzer runs:** a command Stop hook that shells `claude -p`/the API, vs a native "prompt" Stop
   hook. Which is more robust + faster?
3. **Circling detection:** pure LLM judgment, or LLM + a cheap heuristic (e.g. diff of consecutive attempts /
   repeated identical commands)?
4. **Arming UX:** auto-arm inside `/tale-mode:kickoff-phase`/diagnosis, or an explicit lightweight step? Keep it 2 commands
   (no 3rd command) per project owner's preference — arming is a SKILL behavior, not a new command.
5. **Relationship to native `/goal`:** complement (user can still `/goal` on top) or fully replace? Document both.
6. **Headless:** does the goal-file+Stop-hook loop behave under `claude -p`? (Native `/goal` does; verify ours.)
7. **`needs_user` detection quality:** how reliably can the analyzer tell "agent could do this" vs "needs human"?
8. **max_rounds default** + the lifted cap value.
9. **Transcript-tail size** fed to the analyzer (cost vs context).
10. **Failure of the analyzer call itself** (API down): fail safe = exit 0 (let the turn finish), never trap.

## 9. Build plan (for the fresh session — build, don't prototype)
Each step: build **and test its fail-case + pass-case** before moving on (the discipline applies to our own work).
1. **Goal-file convention** + arming behavior (tale-mode/kickoff writes/clears it). Test: armed vs absent.
2. **Stop hook, deterministic-only first** (no analyzer yet): check passes → exit 0 + clear; fails → exit 2 +
   generic "keep going." **Live-test the loop actually iterates and stops** in a real session.
3. **The analyzer** (Haiku call from the hook): build the prompt; test its JSON verdicts on canned transcripts
   (a circling one, a band-aid one, a genuinely-done one, a needs-user one).
4. **Combine** analyzer + deterministic check in the hook (the §4.2 case logic).
5. **Cap config** (lift `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`) + `max_rounds`.
6. **Human-dep pause** path (NEEDS_USER → clean pause + one ask).
7. **tale-mode integration:** the hook ships generically with the skill; SKILL.md documents the loop + arming;
   settings snippet for the user to register the hook + the cap. **Zero project specifics.**
8. **Live-test all three use cases** (simple / multi-phase / debugging) end-to-end.

## 10. Packaging in tale-mode (open-source, general)
> **SUPERSEDED — tale-mode now ships as a Claude Code *plugin*** (see the README). The loop is
> bundled in the plugin's `hooks/hooks.json` (L1 command + L2 read-only Sonnet governor, default-on);
> there is no `settings.example.jsonc` to copy, and install/uninstall is `/plugin`. The notes below
> are the original (pre-plugin) packaging design, kept as build log.
- `hooks/stop-goal-loop.sh` (+ the analyzer caller) — generic; the only project input is the goal-file's `check`.
- `SKILL.md` — a "Autonomous goal loop" section explaining arm → loop → analyzer → pause/done.
- `settings.example.jsonc` — the Stop-hook registration + the cap env, for users to copy.
- The `active-goal.json` convention — documented, generic.
- Nothing in here references any specific app, vendor, or stack. A user on any project supplies their own `check`.
