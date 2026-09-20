---
date: 2026-09-20
keywords: ["format-md", "prettier", "markdown", "emphasis"]
---

# `format-md` rewrites `*emphasis*` into `_emphasis_`

Prettier's markdown printer normalises emphasis markers, so `*and*` written into
a `.md` file comes back from the hook as `_and_`. Observed while adding a rule to
`src/agentic/git/skills/git-changelog/SKILL.md`: the edit tool accepted `*and*`,
and the file on disk read `_and_`.

This matters because the format hook is easy to think of as narrow — the vault
already records it reindenting embedded JSONC and aligning tables — but it also
rewrites inline emphasis in prose with no tables or code blocks anywhere near it.
So the re-read-before-your-next-edit rule applies to plain prose too, not just to
files whose indentation or line numbers can shift.

Practical consequences: never build a later edit's `oldString` from the text you
just wrote (read the file back first), and if you want emphasis to survive
verbatim in a file the formatter owns, write `_foo_` yourself rather than `*foo*`.
