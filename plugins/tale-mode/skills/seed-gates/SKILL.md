---
name: seed-gates
description: >-
  Scan a repo's package.json scripts, CI workflows, and equivalent manifests, then SUGGEST a
  committed .claude/tale-mode.json gate list for tale-mode's Stop-hook loop — suggestions only;
  this skill never writes the config unasked, never trusts it, and never arms anything. Invoke
  ONLY when the user explicitly asks to seed, suggest, or set up tale-mode gates for a repo.
---

# Seed the committed gates (suggest-only)

Help the user pick the `gates` for a committed `.claude/tale-mode.json` — the config tale-mode's
Stop hook enforces during a kickoff phase (once the user trusts its content-hash; see the `trust`
skill). **Your output is a suggestion the user reviews — never silently write the config, and never
touch the trust store.**

## 1. Inventory candidates mechanically — don't guess from memory

Read the repo's own definition of "green":

- every `package.json` → the `scripts` block (root first; workspaces if a monorepo)
- CI workflows → `.github/workflows/*.yml` (or the host's equivalent) — the commands CI actually
  runs are the strongest signal of what "passing" means here
- other manifests as present: `Makefile`, `pyproject.toml`/`tox.ini`, `Cargo.toml`, `go.mod`
  (→ `go test ./...`), a repo-local `tests/` runner script

## 2. Filter hard — a gate runs at EVERY turn-end during a phase

Keep only commands that are **hermetic and terminating**:

- ✅ local + deterministic: typecheck (`tsc --noEmit`), lint, format-check, unit tests, a build
  that's reasonably fast, a repo-local test script
- ❌ anything that doesn't terminate: `dev`, `start`, `serve`, `--watch`
- ❌ anything non-hermetic: network calls, fresh dependency installs, deploy/publish/release,
  E2E needing a live server or credentials, destructive/generative steps (db migrations, codegen
  that rewrites files — a gate must be read-only/idempotent, it runs repeatedly)
- ❌ anything slow enough to hurt: the default per-gate timeout is 120s (`TALE_CHECK_TIMEOUT`);
  a 10-minute suite belongs in CI, not a turn-end gate
- Each gate must be **ONE single-line shell command** (the hook reads them line-wise).

## 3. Verify each candidate by RUNNING it, then present

Run every surviving candidate once from the repo root and record its exit code. A suggested gate
that can't run (missing dep, wrong path) — or that always fails — is worse than none: it would trap
the loop, and the user would "fix" it by weakening the config. Drop or flag anything that isn't
green on the current tree, and say why.

Then present:

1. the suggested `.claude/tale-mode.json` as a fenced snippet, e.g.
   ```json
   { "gates": ["npm run -s typecheck", "npm test --silent"] }
   ```
   (`gates` is the only key the hook reads — don't add decorative fields)
2. one line per gate: where it came from (`package.json scripts.typecheck`, `ci.yml:24`) and its
   verified exit code
3. what you deliberately left out and why (the ❌ list above — name the rejects, don't hide them)

## 4. Hand off — the user decides

Only write the file if the user says so (writing it is safe in itself — it's inert until trusted —
but it's their repo and their review). Then point them at the two user-only follow-ups you must
NOT do yourself: committing the config, and trusting its content-hash (the `trust` skill has the
exact commands). Remind them a later edit to the config changes its hash and needs a re-trust.
