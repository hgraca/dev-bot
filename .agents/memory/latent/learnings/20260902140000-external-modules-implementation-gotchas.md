---
date: 2026-09-02
keywords: ["devbot", "external-modules", "merge_modules_jsonc", "gotcha"]
---

> **SESSION REVERTED (2026-09-02)** — the namespaced model this file documents
> was reverted to named imports (see
> [ADRs/20260902170000-external-modules-named-imports-restored.md](../ADRs/20260902170000-external-modules-named-imports-restored.md)).
> Bullets 1-2 still apply to the restored code; bullet 3 (nested keys) is void.

# External-modules implementation gotchas (2026-09-02)

- `merge_modules_jsonc.py` reads declaration files with plain `json.load` — a `//` comment inside `external-modules.json` makes the merge fail with "cannot read entries file" and, because install.sh prunes stale entries after merging, a broken declaration silently pruned the live vendor clones and config during migration. Declaration files must stay strict JSON; JSONC comments belong in `.devbot.global.jsonc`, never in declaration files.
- The merge script's original `_find_field_value_end` anchored `"external_modules"` to a line start, so single-line configs and configs whose first key follows a comment were treated as having no section → insert appended a SECOND `external_modules` key, corrupting the file. Fixed with a depth-aware scan (root-level keys live at depth 1; probe for the colon; skip comments before the key).
- Nested namespaced keys (`org/repo`) break every place that treats a module name as a single path segment: `.agents` links need parent-dir `mkdir`, storage mirrors and prune/memory-linking must share one sanitizer (`/` → `__`), and the generic lifecycle runners require storage dirs to stay flat.
- The `--remove`/`--update` modes rewrite the `external_modules` section canonically; run format-json AFTER pruning or the file is left misindented (install.sh orders merge → prune → format).

See: ADRs/20260902140000-external-modules-architecture.md
