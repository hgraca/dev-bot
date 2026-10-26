---
date: 2026-10-26
keywords: ["devbot", "format-md", "prettier", "bats"]
aliases: ["format-md on bats", "prettier markdown parser trap"]
---

# Never pass a `.bats` file to `format-md`

`format-md` runs `prettier --parser markdown --print-width 999`, with the parser forced. Pointed at a BATS file it parses the whole test file as Markdown: the `# ===…` header is read as a setext underline and deleted, comment bodies reflow, and `@test` blocks become paragraph text. Verified on `src/agentic/devbot/tests/work-autonomously_tests.bats` — the first changed line was the header rule, which came back as a blank line.

`format-md --check` reports such a file as "1 need formatting"; that is the parser mismatch talking, not a real formatting gap. Plain `prettier --check` on a `.bats` path instead errors with "No parser could be inferred" — the honest answer.

The commit protocol's "run every applicable `format-*` tool" does not make `format-md` applicable to a `.bats` file: there is no markdown in it. Leave BATS out of the formatting set, and treat a `format-md` complaint about one as noise.
