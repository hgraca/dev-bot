---
date: 2026-06-15
keywords: ["shell", "bats", "subshell", "export"]
---

## BATS: `export` inside `$()` subshell does not propagate to parent

When a BATS test helper function is called inside a command substitution (`$(helper)`), it runs in a subshell. Environment variables exported (`export VAR=value`) inside the subshell are NOT visible to the parent BATS test body. The fix: either inline setup directly in the test body, or source a function that runs in the same shell (e.g. `source <(helper_function_body)`, though this is fragile). The safest pattern: repeat setup inline per test rather than extracting to a `$()` helper function.
