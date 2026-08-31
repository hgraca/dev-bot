---
date: 2026-08-22
keywords: ["opencode", "external_directory", "permission", "glob"]
trigger-on: ["opencode-external-directory-glob"]
---

## external_directory globs need ** to cross directories — /tmp/* won't match /tmp/opencode/file.txt

opencode's `permission.external_directory` (and the other path-based permission rules) use glob patterns where `*` does **not** match `/`. A `"/tmp/*": "allow"` entry only matches direct children of `/tmp` (the directory `/tmp/opencode` itself), not nested paths like `/tmp/opencode/file.txt` — those fall through to the next rule (`"*": "deny"`) and get denied. For recursive access to a scratch dir use `"/tmp/**": "allow"`. Symptom: reading a file inside an "allowed" directory is denied even though the directory itself is allowed. The same `**` convention applies to `edit`/`read`/`bash` path rules (docs use e.g. `~/projects/personal/**`).
