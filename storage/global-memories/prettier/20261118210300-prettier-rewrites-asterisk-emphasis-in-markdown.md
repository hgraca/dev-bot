---
date: 2026-11-18
keywords: ["prettier", "markdown", "emphasis", "lint"]
aliases: ["prettier md check fails", "asterisk emphasis"]
---

## Prettier's markdown parser rewrites `*emphasis*` to `_emphasis_`

Prettier normalises emphasis markers in markdown to underscores, so a file written with `*word*` fails `prettier --check` even though the rendering is identical. Any repository that lints all tracked markdown (a `make lint` over `git ls-files '*.md'`) will reject it — including notes under a committed memory or docs tree, which are easy to forget because they are prose rather than code.

Run the project's formatter over prose files before committing them, and remember that the check is part of CI for _every_ pull request: one unformatted tracked document turns the whole board red for everyone, not just the author.
