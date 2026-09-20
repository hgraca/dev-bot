---
date: 2026-09-10
keywords: ["yq", "shell", "yaml", "reformat", "indent"]
trigger-on: ["yq-edit-yaml", "yaml-bulk-edit"]
---

## `yq -i` reindents YAML sequences, producing noisy diffs

Editing hand-formatted YAML with `yq -i` (mikefarah v4) round-trips the whole document and rewrites sequence indentation (indentless `- item` under a key becomes indented), so a one-line change shows unrelated reindentation hunks. For a small, surgical edit to a hand-maintained manifest, prefer a targeted line-based insertion (e.g. a short script that finds the anchor line and inserts at its indentation) over a YAML round-trip; verify with `diff` that only the intended lines changed.
