---
date: 2026-10-16
keywords: ["devbot", "format-yml", "prettier", "edit"]
aliases: ["format hook churn", "yaml re-indent", "prettier tabWidth"]
trigger-on: ["prettier-yaml-edit"]
---

## Editing another project's YAML with the edit tool reformats the whole file

dev-bot's `format-yml` hooks run prettier on the edited file whenever the **target project**
declares prettier (`.prettierrc*`, `prettier.config.*`, or a `package.json` key). Editing a
consumer's `.docker/compose.dev.yml` — 2-space indent while its `.prettierrc` sets
`tabWidth: 4` — via the `edit` tool therefore re-indents the entire file: a 3-spot change landed
as a ~270-line diff, and a follow-up edit built from the pre-format text risks being
fuzzy-spliced into the re-indented file (the audit-51 hazard).

When the change must stay minimal in a prettier-declaring project, apply it with a script
(`python3` exact-string replace, or `git apply`) instead of the `edit`/`write` tools — those do
not emit the `file.edited` event the hook listens for — then confirm with
`git diff --numstat` that only the intended hunks changed.
