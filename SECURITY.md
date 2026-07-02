# Security Policy

Tale Mode is a plugin for Claude Code and OpenAI Codex — Markdown instruction files, a few small
shell hooks, and JSON manifests. There's no server, no build step, and no runtime service. But a
plugin loads into an AI agent's context and can shape what the agent does, so its contents matter.
This policy explains the threat model and how to report a problem.

The whole point of keeping it small is that you can read it. The sections below list every file
that carries any capability, and what each one can and can't do.

## Threat model — what to look at

The core plugin (`plugins/tale-mode/`) is the default install; the governor
(`plugins/tale-mode-governor/`, covered at the end) is a separate opt-in. The complete reviewable
surface:

- `skills/tale-mode/SKILL.md` — the instructions loaded into the model. Read it for anything
  that would steer Claude toward reading secrets, exfiltrating data, weakening security, or
  running destructive commands. (By design it does the opposite.)
- `hooks/stop-goal-loop.sh` + `hooks/hooks.json` — the autonomous-loop **Stop hook**, on by
  default. It is silent on any normal (non-phase, clean) turn, and arms from two sources, both
  under your control:
  1. an **agent-written `.claude/active-goal.json`** — runs *that goal-file's `check` command*
     (shell the agent wrote in your repo); and
  2. a **committed, content-hash-TRUSTED `.claude/tale-mode.json`** — only during a deliberate
     `/tale-mode:kickoff-phase` phase (a session-scoped marker — see `mark-phase.sh` below) **and**
     while the working tree is dirty, it runs that config's `gates`. **A repo's gates never execute
     until you trust their exact content-hash**, by adding it to `~/.claude/tale-mode-trust` — a
     manual, user-only action. The hook and the agent only ever *read* that store, never write it,
     so a malicious repo cannot self-trust. The committed gates are AND-combined with any goal-file:
     the agent's file may *add* a gate but can never *suppress* a committed one. The phase marker
     itself can also arrive as an agent-written `.claude/tale-mode.phase.pending.json` (written by
     the `kickoff-phase` *skill* on hosts without command expansion, e.g. Codex), which the Stop
     hook claims into the session-scoped name at the first turn-end. That adoption grants nothing
     an agent doesn't already have — a marker only *enables* the trust-gated, dirty-gated committed
     gates above, strictly less than the arbitrary-shell goal-file in source 1. Two limits
     of the shared pending name: adoption needs the host's Stop payload to carry a `session_id`
     (without one the file sits inert, fail-safe), and with several concurrent sessions in one
     repo, whichever session's turn ends first claims an unclaimed pending marker (or drops it, if
     that session is already mid-phase) — bounded by the same trust + dirty + `max_rounds` gates,
     and clearable any time with the `end-phase` skill.
  Either way, `check`/`gates` are arbitrary shell run with your privileges to decide whether to keep
  the turn going; the hook appends a JSONL verdict line to a local `.claude/tale-mode.log` audit file
  for each goal-file `check` round and each committed-gate **block** (the command + its last-1200-byte
  output tail — keep these free of secrets, as that tail is persisted at rest locally). No network
  access; disable the log with `TALE_VERDICT_LOG=/dev/null`. Bounded by `max_rounds` + a fail-open.
  **Project root:** on Claude Code the hook anchors on `CLAUDE_PROJECT_DIR` and never trusts the hook
  payload's `cwd` for a blocking decision (a stray sibling goal-file must not trap an unrelated turn).
  On a runtime that doesn't export `CLAUDE_PROJECT_DIR` (e.g. Codex) the loop stays **inert** unless you
  opt in for that runtime — either **`TALE_ALLOW_CWD_ROOT=1`** in the host env (Claude Code) **or** a
  one-time marker file **`~/.tale-mode-allow-cwd-root`** (required on Codex, whose hook subprocesses do
  not inherit the host env config, so the env var never reaches the hook). Either is a deliberate user
  grant in your own home/host; it lets the hook resolve the root from `cwd` (validated as an absolute,
  existing directory). Off by default; enable it only after confirming the Stop-payload `cwd` is the
  stable workspace root.
- `hooks/session-start.sh` + `hooks/hooks.json` — the always-on **SessionStart hook**. On every
  session start it prints a short, fixed reminder of the core disciplines (verify-against-source /
  foundation-first / two-strike) for Claude to read. It reads no repo files, runs no project input,
  makes no network calls, needs nothing beyond the ubiquitous `cat`, and always exits 0 — it can
  never block.
- `hooks/mark-phase.sh` + `hooks/hooks.json` — the **phase-marker hook** (a UserPromptSubmit hook,
  valid on both Claude Code and Codex). It runs on every prompt and acts only when the prompt is a
  `/tale-mode:kickoff-phase` invocation, writing a session-scoped `.claude/tale-mode.phase.<id>.json`
  so the Stop hook knows a deliberate build phase is active (this is what gates the committed-config
  auto-arm above). It reads only the hook payload, writes only that marker, makes no network calls,
  and **always exits 0 with no output** — it can never block or alter your prompt. (On Codex the
  kickoff is invoked as a skill whose prompt may not carry the trigger text, so there the
  `kickoff-phase` skill writes the pending marker the Stop hook adopts — see above — and the
  agent-written `.claude/active-goal.json` stays the ad-hoc path.)
- `output-styles/tale-mode.md` — an **opt-in** output style (you select it via `/config`): plain
  Markdown instructions that shape how Claude works, inert until you choose it.
- `agents/plan-reviewer.md` — a subagent granted `Bash` + `WebFetch`. These run only when you
  invoke a review, under Claude Code's permission prompts.
- `commands/plan-phase.md`, `commands/kickoff-phase.md` — Claude Code slash-command prompt
  templates; no code execution of their own.
- `skills/plan-phase/SKILL.md`, `skills/kickoff-phase/SKILL.md` — the same phase workflows as
  skills (the cross-platform trigger, since Codex has no user slash commands); instructions only,
  no code execution.
- `skills/trust/SKILL.md`, `skills/seed-gates/SKILL.md`, `skills/end-phase/SKILL.md` — helper
  skills, tuned to load only on an explicit ask; instructions only, no code execution. `trust`
  documents the two user-only grant files and forbids the agent writing them; `seed-gates`
  suggests gates and never writes the config unasked (and never the trust store); `end-phase`
  clears the phase marker(s) — the explicit off-switch for committed-gate enforcement.

### The governor (optional companion — `plugins/tale-mode-governor/`)

The governor is a **separate plugin you install only if you want it**. It adds one capability the
core plugin doesn't have: it spawns a headless, read-only model call on your behalf — but only
when the autonomous loop is genuinely stuck. One file carries all of it:

- `hooks/governor.sh` (a single `type:"command"` Stop hook, both hosts). At every turn-end it is a
  free bash check that exits silently unless *all* of these hold: this session's goal-file exists,
  it has failed **exactly 2** rounds (once per stuck goal, never per-round), and — on Codex —
  you've granted the same `~/.tale-mode-allow-cwd-root` opt-in the core loop uses. Only then does
  it spawn **one** reviewer:
  - on Claude Code, `claude -p` pinned to `claude-sonnet-4-6` by default (`TALE_GOVERNOR_MODEL` overrides), with the built-in tool set restricted to
    `Read`/`Grep`/`Glob` (no shell, no writes) **and** `--strict-mcp-config` stripping every MCP
    server from the child — so nothing write-capable or external is offered at all; it draws from
    your own subscription;
  - on Codex, `codex exec` locked to `--sandbox read-only` — OS-enforced (Seatbelt / seccomp),
    probe-verified unable to write even `/tmp`.
  A sentinel environment variable stops the child from re-triggering this hook or the core loop
  (no recursion — verified live on both mechanisms), the run is time-bounded, and the reviewer's
  finding is surfaced as an *advisory* message — it can never block a turn or change the loop's
  decision. Kill switch on both hosts: `TALE_GOVERNOR=0`. The full design, and the live probes
  that justified building it, are in [`docs/codex-governor-spike.md`](docs/codex-governor-spike.md).

### Not part of the plugin

A repo's committed gate config (`.claude/tale-mode.json`) and the trust store (`~/.claude/tale-mode-trust`)
are **not** part of the plugin — the config lives in each consumer repo, and you review it at the moment
you choose to trust its content-hash. Until you do, it is inert (its gates never run).

Install/uninstall is Claude Code's built-in `/plugin` mechanism — it records the plugin in a
managed `enabledPlugins` registry and does **not** hand-edit your `settings.json` hooks or
permissions. There is **no telemetry and no background network activity** anywhere in the project.

## Reducing your exposure

- Read the files above before installing — a couple of minutes, which is the point of keeping
  the plugin tiny. The autonomous-loop Stop hook is on by default; if you'd rather it weren't,
  `/plugin disable tale-mode@tale-mode` turns the whole plugin off without uninstalling.
- Pin to a reviewed version rather than tracking `main`, especially on shared or work machines —
  review a specific commit on GitHub before installing.
- Run Claude Code with least privilege (its permission prompts, `/permissions` deny-lists, or a
  sandbox / dev container) — good practice for *any* third-party plugin, not just this one.

## Reporting a vulnerability

Please report privately rather than opening a public issue:

- **Preferred:** use GitHub's **"Report a vulnerability"** button under this
  repository's **Security** tab (private security advisories).
- If that's unavailable, open a minimal public issue saying only "security —
  please enable private reporting," with no details.

You'll get an acknowledgement as soon as possible, and credit in the fix if you'd
like it. There's no bug-bounty program — this is a free, single-maintainer
project — but reports are genuinely appreciated.

## Supported versions

Fixes land on `main`. Pin to a commit you've reviewed, and re-review when you
update.
