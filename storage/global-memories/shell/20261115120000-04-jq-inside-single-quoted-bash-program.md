---
date: 2026-11-15
keywords: ["shell", "jq", "quoting", "apostrophe"]
---

## An apostrophe inside a single-quoted `jq` program silently ends the program

`panel_body="$(jq -nc '{ ... }')"` is a single-quoted string, so a comment such as `// provider's session` closes it at the apostrophe; bash then reports a syntax error several lines lower, at an unrelated line, because it is parsing JSON as shell. Keep apostrophes out of jq programs embedded that way. Separately, jq has no `//` comments — `//` is its alternative operator — so an explanation written as `// text` becomes an expression and fails with "May need parentheses around object key expression". Put the explanation in a bash comment above the assignment and leave the jq program bare.
