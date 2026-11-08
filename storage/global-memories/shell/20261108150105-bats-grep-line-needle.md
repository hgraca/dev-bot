---
date: 2026-11-08
keywords: ["shell", "bats", "grep", "test-needle"]
---

## A BATS `grep -F` assertion fails when the phrase wraps across lines

`grep` matches per line, so a `grep -qF` test needle that spans a line break in the source file never matches even though every word is present — this bites whenever the source is hard-wrapped prose such as a Markdown skill or agent file. A wrap like `ask the user whether to` / `enable the MCP before continuing` breaks `grep -qF 'ask the user whether to enable the MCP'`, so keep each needle on one source line (reflow the source or shorten the phrase) and confirm the needle with `grep -qF` before trusting the test. Two adjacent traps: pass `--` before a pattern that begins with a dash (`grep -qF -- '--key mcps'`), and never read a failing run only through `tail` — the failure scrolls out of the tailed window, so check the runner's exit code.
