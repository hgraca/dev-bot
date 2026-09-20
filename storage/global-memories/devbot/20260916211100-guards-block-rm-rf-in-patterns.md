---
date: 2026-09-16
keywords: ["devbot", "guards", "guard-rules", "bash-guard"]
trigger-on: ["devbot-guards", "devbot-guard-false-positive"]
---

## devbot's guard blocks a command when the forbidden pattern appears anywhere in it — including inside a grep pattern

The guard rules match the **command text**, so a read-only command that merely *mentions* a blocked pattern is refused: `grep -n "rm -rf" somefile` is blocked with `[guards] Command blocked: rm -rf is blocked`, even though nothing is deleted. The refusal is correct by design (the guard cannot know intent) and is not an error to route around. Rephrase the search instead of advertising the pattern — e.g. `grep -nE "rm -r[f]"` (bracket trick) or search for a nearby unique token. Expect the same for any guarded pattern used in a filter, a heredoc, a commit message, or an echo.
