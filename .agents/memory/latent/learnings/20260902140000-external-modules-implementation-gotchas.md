---
date: 2026-09-02
keywords: ["devbot", "external-modules", "merge_modules_jsonc", "gotcha"]
see: ["ADRs/20260902170000-external-modules-named-imports-restored.md"]
superseded_by: ["ADRs/20260902170000-external-modules-named-imports-restored.md"]
---

# External-modules merge-script gotchas

- `merge_modules_jsonc.py` reads declaration files with plain `json.load` — a `//` comment inside `external-modules.json` makes the merge fail with "cannot read entries file" and, because `install.sh` prunes stale entries after merging, a broken declaration silently pruned the live vendor clones and config during migration. Declaration files must stay strict JSON; JSONC comments belong in `.devbot.global.jsonc`, never in declaration files.
- The merge script's original `_find_field_value_end` anchored `"external_modules"` to a line start, so single-line configs and configs whose first key follows a comment were treated as having no section → the insert appended a SECOND `external_modules` key, corrupting the file. Fixed with a depth-aware scan (root-level keys live at depth 1; probe for the colon; skip comments before the key).
