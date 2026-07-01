---
name: trust
description: >-
  Reference for tale-mode's two user-only opt-in files — the committed-gate trust store
  (~/.claude/tale-mode-trust) and the Codex cwd-root opt-in (~/.tale-mode-allow-cwd-root) — and
  their security model. Invoke ONLY when the user explicitly asks how to trust a repo's committed
  tale-mode gates, about the "content-hash is NOT trusted" notice, or how to enable the autonomous
  loop on Codex. Do NOT load this proactively, and NEVER write either file yourself — both grants
  are manual, user-only actions.
---

# Trusting tale-mode's gates and opt-ins

tale-mode's Stop-hook loop has **two separate user-only grant files**, both living in the *user's
home* (never in a repo). Your job with this skill is to **explain them and hand the user the exact
commands — never to run those commands yourself.** Writing either file is the user's deliberate
act; an agent (or a cloned repo) doing it on their behalf defeats the security model.

## 1. The committed-gate trust store — `~/.claude/tale-mode-trust`

**What it gates.** A repo may commit `.claude/tale-mode.json` with a `gates` list (arbitrary shell,
each entry running as one script). During a deliberate kickoff phase with uncommitted changes, the Stop
hook (`hooks/stop-goal-loop.sh`) runs those gates and blocks the turn until they're green — but
**only if the file's exact content-hash is listed in the trust store**. No listed hash → the gates
never execute; the hook instead shows a one-time "review and trust" notice containing the hash.

**Why a content-hash.** Trusting the *content* (not the path) means any edit to the config —
including a malicious gate slipped into a pull — invalidates the trust and the gates go inert until
the user re-reviews and re-trusts the new hash.

**How the user grants it** (after actually reading the gates in `.claude/tale-mode.json`):

```bash
shasum -a 256 .claude/tale-mode.json     # macOS; on Linux: sha256sum .claude/tale-mode.json
echo "<that-hash>  # <repo-name> tale-mode gates" >> ~/.claude/tale-mode-trust
```

One hash per line; anything after whitespace is a comment. Revoke by deleting the line. The store
path can be overridden with `TALE_TRUST_STORE` (used by the test suites).

**Hard rule (D3):** the hook and the agent only ever **read** this store. If you (the agent) are
asked to "just trust it," decline and show the commands — the user reviews the gates, the user
writes the line. A repo whose gates self-trust is exactly the attack this design prevents.

## 2. The Codex cwd-root opt-in — `~/.tale-mode-allow-cwd-root`

**What it gates.** The Stop hook anchors on `CLAUDE_PROJECT_DIR` as the trusted project root and
refuses, by default, to resolve a root from the hook payload's `cwd` for a *blocking* decision (a
stray goal-file under an agent-controlled cwd must never trap an unrelated turn). Codex does not
export `CLAUDE_PROJECT_DIR`, so there the loop stays **inert** until the user opts in to resolving
the root from the session `cwd` (validated as an absolute, existing directory).

**How the user opts in** (once, after confirming their Codex Stop-payload `cwd` is the stable
workspace root):

```bash
touch ~/.tale-mode-allow-cwd-root
```

Revoke with `rm ~/.tale-mode-allow-cwd-root`.

**Why a file and not an env var.** `TALE_ALLOW_CWD_ROOT=1` also works on Claude Code — but Codex
does not pass host env config into hook subprocesses (verified by a live probe), so on Codex the
env var never reaches the hook and the marker file is the working mechanism.

**On Claude Code this file has no effect:** `CLAUDE_PROJECT_DIR` is always set for hooks, so the
cwd branch is never taken and Claude Code stays strict regardless.

## The security model, in one paragraph

Both files are **per-user grants in the user's own home** — a cloned repository cannot ship them,
an agent must not write them, and the hook only reads them. The trust store binds execution to a
reviewed *exact content* (re-review on every change); the cwd-root file is a one-time *runtime
capability* grant for hosts without a trusted project-root env. Everything stays fail-safe without
them: untrusted gates don't run, and on Codex without the opt-in the loop simply never engages.

Full threat model: `SECURITY.md` at the repo root. Source of truth for the mechanics:
`hooks/stop-goal-loop.sh` (root resolution + `_hash_trusted`).
