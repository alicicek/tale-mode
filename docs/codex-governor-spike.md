# Codex governor spike — go/no-go (research only, nothing shipped)

**Date:** 2026-07-01 · **Verdict: CONDITIONAL GO** — a `codex exec`-based L2 governor is
*buildable safely*, but only behind three deterministic guards proven below, and it must not ship
until three **owner-run live-Codex smokes** and a `/security-review` pass. This note is the
deliverable of the Phase F spike (`docs/cross-platform-plan.md` Phase F; `docs/remaining-work.md`
Lane 4). No governor code ships with it.

**Sources.** OpenAI Codex source `openai/codex` @ `d059658` (2026-07-01, release rust-v0.142.5),
the official hooks/sandboxing/config docs (developers.openai.com/codex), the local
`codex-cli 0.142.4` (`codex exec --help`), and the owner's live `~/.codex/config.toml`
(`sandbox_mode="workspace-write"`, `approval_policy="never"` at :4-5; per-hook
`[hooks.state].trusted_hash` entries for tale-mode's three hooks at :299-306). File paths below
are `codex-rs/…` in that repo.

## The three questions, answered

### (a) Does `codex exec` fire Stop hooks → recursion? YES — hazard confirmed, guard exists

- Hooks are dispatched from **core** session code shared by every frontend: turn end calls
  `run_turn_stop_hooks` (`core/src/session/turn.rs:373` → `core/src/hook_runtime.rs:298`), and an
  e2e test runs the real `codex exec` binary and asserts a SessionStart hook executed
  (`exec/tests/suite/hooks.rs`). Plugin hooks load in exec mode too
  (`hooks/src/engine/discovery.rs:209+`).
- Hook **trust is persisted per `CODEX_HOME`**, not per session
  (`[hooks.state]."<source>:<event>:<pos>".trusted_hash`, `config/src/hook_config.rs:20-33`) — so
  a child `codex exec` spawned *from our Stop hook* inherits the parent's trust and **re-fires the
  same trusted Stop hook at its own turn end. Unguarded, that is infinite recursion.**
- The built-in `stop_hook_active` flag is **in-session only** (`hooks/src/events/stop.rs:23-34`);
  it does not protect across a spawned child. Codex sets **no** "already inside codex" marker in
  hook subprocess env (`CODEX_SANDBOX*`/`CODEX_THREAD_ID` go only to *model-command* envs,
  `core/src/spawn.rs:20-25`, `core/src/unified_exec/process_manager.rs:1118-1123`).
- **The guard (deterministic):** hook subprocesses inherit the parent process env with no
  `env_clear` (`hooks/src/engine/command_runner.rs:115`), and a child codex passes its env on to
  *its* hook subprocesses. So the governor script exports a sentinel
  (e.g. `TALE_GOVERNOR_ACTIVE=1`) before spawning `codex exec`; the script's own first line exits
  0 when the sentinel is set → recursion depth capped at 1, by the same env-inheritance mechanism
  that creates the hazard. Belt: `--ignore-user-config` on the child empties the user config layer
  (`config/src/loader/mod.rs:427-439`) → all trust state gone → non-managed hooks are *skipped*
  (`hooks/src/engine/discovery.rs:507-545`) — blunt (drops the rest of user config) but an
  independent second stop.

### (b) Is read-only enforceable under `approval_policy="never"`? YES

- `codex exec -s read-only` OS-sandboxes **model-generated commands**: Seatbelt on macOS,
  seccomp + bubblewrap on Linux (`sandboxing/src/manager.rs:59-73`; Landlock is legacy/deprecated).
  Linux caveat: requires `bwrap` installed.
- **The CLI flag beats config.toml:** `sandbox_mode_override.or(self.sandbox_mode)`
  (`config/src/config_toml.rs:753`) — so `-s read-only` overrides the owner's
  `sandbox_mode="workspace-write"`. `approval_policy="never"` stays in effect, which is exactly
  right for a governor: nothing prompts, and a write attempt just fails inside the read-only
  sandbox. This is materially *stronger* than the Claude Code governor's tool-allowlist (that's
  policy; this is OS enforcement).
- Nuance: the *hook script itself* runs unsandboxed (`command_runner.rs` uses a plain
  `$SHELL -lc`) — same standing as every tale-mode hook today; only the child's model commands
  get the sandbox.

### (c) Platform detection? YES — un-prefixed `PLUGIN_ROOT`

- Codex sets exactly four extra vars for plugin hook subprocesses: `PLUGIN_ROOT`, `PLUGIN_DATA`
  (+ the `CLAUDE_*` pair "for OOTB compat", `hooks/src/engine/discovery.rs:228-235`). The docs
  call `PLUGIN_ROOT` "a Codex-specific extension"; Claude Code's plugins reference documents only
  the `CLAUDE_*` forms. Detector: **`[ -n "$PLUGIN_ROOT" ] && [ -z "$CLAUDE_PROJECT_DIR" ]`**
  (belt-and-braces: CC always sets `CLAUDE_PROJECT_DIR` for hooks; Codex never does). Never use
  `CODEX_HOME` or bare `CLAUDE_*` — both proven poisoned on this machine
  (`docs/cross-platform-plan.md` C4c). Residual: Claude Code is closed-source, so "CC never sets
  `PLUGIN_ROOT`" is docs-based, not source-proven — the belt covers that.

## Also settled by this spike

- **`shell_environment_policy.set` never reaches hooks** (applied only in the model-shell path,
  `core/src/unified_exec/process_manager.rs:1113-1167`; zero refs in the hooks crate) — confirms
  the file-opt-in design of `~/.tale-mode-allow-cwd-root` was the right call, from source this time.
- **Hook trust hashes the hook *definition*** (the hooks.json entry, keyed positionally by
  source + event + position). tale-mode 2.2.0 does not touch `hooks.json`, so the owner's existing
  `[hooks.state]` trust entries should survive the update — worth a glance at the first Codex
  session after updating (a "modified, needs review" hook would be silently skipped, not broken).

## Why NOT ship it now (the gate)

1. **Owner smoke 1 — recursion probe (BLOCKS build):** on live Codex, a throwaway trusted Stop
   hook exports the sentinel, spawns `codex exec --sandbox read-only -o /tmp/gov.txt "reply DONE"`,
   and proves: exactly one child, child's Stop hook exits on the sentinel, no fork bomb.
2. **Owner smoke 2 — sandbox probe:** the child, told to `touch /tmp/PWNED`, must fail under
   `-s read-only` with the owner's real config (`approval_policy="never"`,
   `network_access=true`).
3. **Owner smoke 3 — detection probe:** dump env from a tale-mode hook on live Codex; confirm
   `PLUGIN_ROOT` present + `CLAUDE_PROJECT_DIR` absent (and the reverse on Claude Code).
4. **`/security-review`** on the actual governor script before any release (auto-exec surface).
5. **Economics/design:** it adds a model call at stuck turn-ends; per the L2 precedent it must be
   a separate opt-in (the `tale-mode-governor` plugin — currently `enabled = false` on the owner's
   own Codex, which is a signal about demand). Per-hook trust means Codex users must explicitly
   trust the new hook anyway — the opt-in is structural.

**If the three smokes pass**, the build is small: one `type:"command"` Stop-hook script in the
governor plugin, gated on the platform detector + the sentinel + `rounds ≥ 2` in the goal/phase
file, spawning `codex exec -s read-only --ephemeral --skip-git-repo-check` with a read-only
review prompt and `-o` capture. Until then: **no build.** The Claude Code governor stays as-is;
Codex users rely on the §5 fresh-context review.
