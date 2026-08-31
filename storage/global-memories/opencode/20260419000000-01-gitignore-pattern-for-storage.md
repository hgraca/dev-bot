---
date: 2026-04-19
keywords: ["opencode"]
---

## `.gitignore` pattern for `storage/`

Correct pattern:

```
storage/*
# storage/opencode.jsonc is generated per-machine by the installer — MUST NOT be tracked
!storage/.gitkeep
```

`storage/secrets/` does not need a separate exclusion line because `storage/*` already ignores everything; the `!` exceptions whitelist only what should be tracked. `storage/opencode.jsonc` must NOT be whitelisted — it is machine-specific.
