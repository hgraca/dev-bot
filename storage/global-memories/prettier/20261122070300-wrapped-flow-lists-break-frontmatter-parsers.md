---
date: 2026-11-22
keywords: ["prettier", "frontmatter", "yaml", "flow-list", "prettier-ignore"]
aliases: ["wrapped list", "one-line manifest", "prettier-ignore in yaml"]
---

## Prettier wraps long YAML flow lists, and single-line parsers then drop them

In markdown front matter, prettier formats the YAML block and wraps a flow list that crosses `printWidth` onto several indented lines — `skills: ["a", "b", …]` becomes `skills:` followed by `"a",` lines. Any parser that reads front matter line-by-line and expects the list on one line (the pattern in this repo's `gather-module-docs.py`) then reads the key as an empty value and silently loses every entry; it does not error, so the loss is invisible until something is missing from a generated page. `# prettier-ignore` on the line immediately above the key is honoured inside YAML front matter and keeps the list inline. Verify after any front-matter edit: run the formatter, then re-check that the parser still sees the entries.
