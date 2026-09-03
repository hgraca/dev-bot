---
date: 2026-09-03
keywords: ["devbot", "audit", "fixture", "baseline", "guards", "search-memories", "graphify.bkp", "claudecode"]
---

# Audit 38/39 findings are stale-baseline false positives (guards, search-memories); one latent gap remains (graphify.bkp)

Audit reports 38 (opencode) and 39 (claudecode) reported two FAILs that earlier
audits (32/33/36/37) had already fixed and verified. Root cause of the
confusion: the 38/39 fixtures were built from an **older dev-bot baseline**
(both reports omit the install rev that audits 34–37 stated), so they describe
pre-fix code. Verified against current `src/`:

| Report claim                                                                                                                       | Current source                                                                                                                                                                                                     |
| ---------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 38 FAIL-1: guards inert — "`on-hooks.ts` reads `process.env.DEVBOT_ROOT`"                                                          | `on-hooks.ts` uses `resolveGlobalConfigPath(DEV_BOT_ROOT, process.env)` (plugin-root realpath first, `DEV_BOT_ROOT` env) — audit-32 fix; audit-37 verified guards blocking live. No `DEVBOT_ROOT` env read exists. |
| 38/39 FAIL-2: `search-memories` default → "Collection not found: devbot" — "`resolve_collection` falls back to literal `"devbot"`" | `resolve_collection` returns `project_name` else `project_root.name` (basename, audit-32/33 fix; docstring cites the "devbot" bug as fixed).                                                                       |
| 38 NOTE-1: `tree --maxdepth` unsupported                                                                                           | Tool implements `--max-depth`/`-L` (audit-28); the audit used the unadvertised `--maxdepth` spelling — correctly rejected (audit-26 NOTE-4).                                                                       |
| 38 NOTE-2: `php` absent in container                                                                                               | `tests/test-project/Dockerfile:33` apt-installs `php-cli`; the test image simply wasn't rebuilt. Infra, not code.                                                                                                  |

**Action taken (2026-09-03): none — verified stale, no code change.** Audit-37
(pre-fix baseline comparison run) is the healthy counterpart; audits 36/37 ran
the local branch (rev `3cb91c2`+), 38/39 ran the baseline.

## One latent gap remains (audit-39, not addressed)

`_link_claude_skills_flat` (claudecode/init.sh ~L473) classifies a **real-file**
`.claude/skills/<name>/SKILL.md` as user content unconditionally — only a
_symlinked_ SKILL.md into dev-bot paths is skipped. If the external `graphify`
CLI installs a real-file `.claude/skills/graphify/` on each run, every reinit
migrates it as "user" and collision-preservation suffixes `.bkp` → a live
duplicate `graphify.bkp` skill that keeps re-appearing (potentially `.bkp.bkp`).
Not fixed: the trigger is external-CLI install ordering (unverifiable without a
claudecode fixture run) and the flatten code is delicate (review conventions
F1–F4, zero test coverage). If revisited: skip real-file dirs whose SKILL.md
content matches dev-bot's canonical copy or that carry a known tool marker.

## Update: audits 40/41 (2026-09-03, same session)

Audits 40 (claudecode) and 41 (opencode) repeated the same stale claims
(guards `DEVBOT_ROOT`, search-memories `"devbot"` fallback) and added one
crash report: audit-40's session-end WARN showed unhandled `write EPIPE` in
`chrome-devtools`/`codebase-index`/`playwright` `.agents/logs/*-mcp.log` — the
audit-35 signature again. Disposition, verified on disk + source:

- **EPIPE traces exist only in the `audit-35` and `audit-40` log archives**
  (`tests/test-project/.agents/logs/devbot-audit-*/`); audits 36–39 and 41 are
  clean — including audit-36 (claudecode, rev `3cb91c2` WITH the guard fix).
  audit-40's fixture therefore predates `feab74d8` (round-1 guard) — same
  stale-baseline class as 38/39.
- **Guard chain now proven through the npx hop**: `mcp-stdio-wrapper.js`
  spawns `npx -y <server>`; a hermetic bats test (`guard: NODE_OPTIONS
propagates through npx to the spawned server`, wrapper tests) asserts the
  server process sees `NODE_OPTIONS=--require=<mcp-epipe-guard.js>` — the
  crash site (server's own stdout) is covered.
- **audit-41 FAIL-3 (project `app` collection cold at launch) is a known,
  accepted trade-off**: the delete→prune warm-up lives in `start.sh`
  (`_devbot_prune_memories_detached`), so harnesses launched directly (the
  fixture's `test-oc.sh`/`test-cc.sh` bypass `devbot`) do not warm the vault
  until the first latent/learnings edit. Documented when the session.created
  hook was removed (audit-36 fix); `devbot` start is the canonical entry.
- audit-40/41 also omit the installed dev-bot rev (as 38/39 did) — the runner
  should print it or fixtures should pin the local branch rev.

## Guidance for future audit rounds

- Build fixture containers from the **local branch rev** (as 36/37 did), not a
  baseline, or state the installed rev in the report header (38/39 omitted it).
- Before treating a "regression" as real, grep current `src/` for the cited
  root cause — several audits describe code that no longer exists.
- `tests/test-project/` is the dev-bot test fixture (test-oc/test-cc runners +
  Dockerfile); infra follow-ups live there (e.g. rebuild image to ship php-cli).
