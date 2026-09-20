---
date: 2026-09-20
keywords: ["format-md", "prettier", "line-length", "git-changelog"]
---

# `format-md` cannot enforce a line length — it runs prettier with no wrapping

`src/agentic/format-md/tools/format-md.py` line 43 invokes prettier as
`["prettier", "--parser", "markdown", "--print-width", "999", "--ignore-path", "/dev/null"]`
— the 999 print width is deliberate ("no line wrapping"), so the formatter
**never reflows, wraps, or collapses markdown prose or list items**. It aligns
table columns and normalises indentation, nothing more.

Consequence for any rule about line length in a markdown artifact (the
`devbot:git-changelog` 72-character bullet cap is the concrete case): the hook
will not enforce it, and it will not undo a violation. A line-length rule must
be written into the artifact's own text — the skill or template — because
nothing else in the pipeline constrains it. `.editorconfig` likewise sets only
indent, LF, and a final newline; it carries no `max_line_length`. Only a test
that parses the artifact can enforce such a rule mechanically.

Do not reach for `format-md` as a fix for over-long lines, and do not assume a
long line was wrapped by the hook before you see it.
