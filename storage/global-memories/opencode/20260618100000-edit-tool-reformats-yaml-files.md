---
date: 2026-06-18
keywords: ["opencode", "edit", "yaml", "formatting"]
---

## edit tool reformats YAML files — strips quotes, removes blank lines, reformats arrays

The `edit` tool applies automatic YAML formatting when modifying `.yml`/`.yaml` files, converting the entire file: quotes removed from scalar values, blank lines between top-level keys deleted, inline arrays (e.g. `["CMD-SHELL", "curl ..."]`) reformatted to multi-line form. This contradicts the earlier finding that edit only reformats JSON/JSONC — YAML is also affected. The diff shows many unintended cosmetic lines polluting surgical change. Workaround: use `sed -i` via `bash` tool to insert/delete lines in YAML files when surgical precision matters. Avoid the `edit` tool for YAML files unless you accept full-file reformatting.
