---
date: 2026-06-12
keywords: ["shell", "bash", "glob", "quoting", "variable-expansion"]
---

## Bash glob expansion with variables: trailing slash must be inside double quotes

When using a variable followed by a glob pattern like `*/`, the trailing slash must be INSIDE the double quotes around the variable: `"${BASE}/"*/`. Using `"${BASE}"*/` produces a different glob that matches directories starting with BASE's value rather than subdirectories of BASE. For example, `"${external_base}"*/` matches `external-agentic-modules*` (directories starting with that name) instead of `external-agentic-modules/*/` (subdirectories).

Always use `"${VAR}/"*/` pattern when iterating subdirectories of a variable path.
