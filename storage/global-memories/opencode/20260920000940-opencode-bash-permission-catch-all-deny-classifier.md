---
date: 2026-09-20
keywords: ["opencode", "permissions", "bash-deny", "agent-permission"]
trigger-on: ["opencode-agent-permission", "opencode-bash-permission"]
---

## A structured `bash` permission with a `"*": deny` catch-all still reads as bash-denied

To let a bash-denied agent run exactly one command, replace the scalar with a map whose catch-all is the deny:

```yaml
permission:
  bash:
    "*": deny
    "*record-grades.py*": allow
```

opencode evaluates the last matching rule, so the broad deny goes first and the narrow allow last. dev-bot's shell-strategy test helper classifies this correctly: it recognises `bash: deny`, and also a `bash:` map whose catch-all `"*"` is a deny — so such an agent stays in the "cannot shell" class, keeps its PTY-deny invariant, and needs no shell-strategy skill. A partial map with no catch-all reads as not-denied.

Reach for this instead of deleting `bash: deny`: removing the scalar makes the agent fully shell-capable, which breaks the `every shell-capable agent loads the shell-strategy skill` invariant, empties the `at least one agent cannot shell` canary, and contradicts read-only agent prose.
