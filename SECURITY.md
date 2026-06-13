# Security Policy

Tale Mode is a Claude Code **skill** — a set of Markdown instruction files plus a
small install script. There's no server, no build step, and no runtime service.
But a skill is loaded into an AI agent's context and can shape what the agent
does, so its contents matter. This policy explains the threat model and how to
report a problem.

## Threat model — what to look at

The complete, reviewable surface is five files:

- `SKILL.md` — the instructions loaded into the model. Read it for anything that
  would steer Claude toward reading secrets, exfiltrating data, weakening
  security, or running destructive commands. (By design it does the opposite.)
- `install.sh` — runs on *your* machine. It only uses `mkdir`/`cp`/`cmp` to copy
  files into `~/.claude` (or `./.claude` with `--project`). No network access.
- `claude-code/agents/plan-reviewer.md` — a subagent granted `Bash` + `WebFetch`.
  These run only when you invoke a review, under Claude Code's permission prompts.
- `claude-code/commands/plan-phase.md`, `claude-code/commands/kickoff-phase.md` —
  slash-command prompt templates; no code execution of their own.

There is **no telemetry and no background network activity** anywhere in the
project.

## Reducing your exposure

- Read the five files above before installing — a couple of minutes, which is the
  point of keeping the project tiny.
- Pin to a reviewed commit rather than tracking `main`, especially on shared or
  work machines:

  ```bash
  git clone https://github.com/alicicek/tale-mode && cd tale-mode
  git checkout <commit-sha>   # a commit you've read
  ./install.sh
  ```

- Run Claude Code with least privilege (its permission prompts, `/permissions`
  deny-lists, or a sandbox / dev container) — good practice for *any* third-party
  skill, not just this one.

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
