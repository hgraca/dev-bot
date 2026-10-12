---
date: 2026-10-12
keywords: ["shell", "ripgrep", "rg", "cli-flags"]
aliases: ["rg -r recursive confusion", "ripgrep replace flag", "rg replace not recursive"]
---

## `rg -r` is `--replace`, not recursive — ripgrep is already recursive

`rg` is recursive by default, so there is no `-r`/`--recursive` flag: `-r` is
`--replace TEXT`. Running `rg -rn "pattern" path` therefore silently replaces every match
with the literal `n` in the printed output — it does not error, so it reads like garbled
results. Example: `rg -rn "Annex of" src/` prints `## n \`devbot:…\``instead of the
matched line, which looks like the file contains`n`. Use plain `rg -n "pattern" path`for
line numbers (recursion is implicit); reach for`-r` only when you actually want the match
text substituted with a replacement string.
