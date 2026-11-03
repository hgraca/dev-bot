---
date: 2026-11-03
keywords: ["devbot", "format-yml", "prettier", "hook", "workflow"]
aliases: ["format hook reindent", "tabWidth 4 yaml", "hook reformatted my file"]
superseded_by: ["devbot/20261103173500-format-tools-now-honour-prettierignore.md"]
---

## The format-yml hook rewrites the whole YAML file, ignoring the repo's .prettierignore scoping

> **Superseded by** `devbot/20261103173500-format-tools-now-honour-prettierignore.md` (2026-11-03) — the tools now honour `.prettierignore`; the workaround below no longer applies.

Editing one line of a committed workflow can come back as a 195-line diff: the `format-yml` hook
runs prettier with the project `.prettierrc`, so a repo with `"tabWidth": 4` gets every
2-space-indented YAML file re-indented, folded block scalars (`>-`) joined onto one line, and quotes
normalised. The repo's own `.prettierignore` does not restrain the hook — a project that scopes
prettier to `resources/assets/js/**` still sees its `.github/workflows/*.yml` rewritten, so the
reformat is not even what the project's `prettier` script would do.

Because prettier does not change YAML semantics for these cases, the damage is review noise, not a
behaviour change — but it buries the real edit and can make a focused PR unacceptable.

When this happens: `git checkout -- <file>` to restore, re-apply only the intended substitution
outside the edit tool (a deterministic script or `git apply`), then confirm with `git diff --stat`
that the change is the expected size before committing. Report the reformat to the human rather than
shipping it, and treat "committed YAML indentation" as the target style, not `.prettierrc`.
