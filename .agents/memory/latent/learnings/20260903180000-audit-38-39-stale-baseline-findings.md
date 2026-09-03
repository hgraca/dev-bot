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

## Guidance for future audit rounds

- Build fixture containers from the **local branch rev** (as 36/37 did), not a
  baseline, or state the installed rev in the report header (38/39 omitted it).
- Before treating a "regression" as real, grep current `src/` for the cited
  root cause — several audits describe code that no longer exists.
- `tests/test-project/` is the dev-bot test fixture (test-oc/test-cc runners +
  Dockerfile); infra follow-ups live there (e.g. rebuild image to ship php-cli).
