# Security Policy

Tale Mode is a Claude Code **plugin** — a set of Markdown instruction files, one small
Stop-hook shell script, and JSON manifests. There's no server, no build step, and no runtime
service. But a plugin is loaded into an AI agent's context and can shape what the agent does,
so its contents matter. This policy explains the threat model and how to report a problem.

## Threat model — what to look at

The complete, reviewable surface (all under `plugins/tale-mode/`):

- `skills/tale-mode/SKILL.md` — the instructions loaded into the model. Read it for anything
  that would steer Claude toward reading secrets, exfiltrating data, weakening security, or
  running destructive commands. (By design it does the opposite.)
- `hooks/stop-goal-loop.sh` + `hooks/hooks.json` — the autonomous-loop **Stop hook**, on by
  default. It does nothing until the agent arms a `.claude/active-goal.json`; when armed it runs
  *that goal-file's `check` command* (a shell command the agent wrote in your repo) to decide
  whether to keep the turn going. No network access; bounded by `max_rounds` + a fail-open.
- `agents/plan-reviewer.md` — a subagent granted `Bash` + `WebFetch`. These run only when you
  invoke a review, under Claude Code's permission prompts.
- `commands/plan-phase.md`, `commands/kickoff-phase.md` — slash-command prompt templates; no
  code execution of their own.

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
