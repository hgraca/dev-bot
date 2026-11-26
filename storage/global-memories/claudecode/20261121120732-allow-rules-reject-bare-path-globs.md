---
date: 2026-11-21
keywords: ["claudecode", "permissions", "allow-rules", "headless", "acceptEdits"]
---

## Claude Code allow rules reject a bare path; use `permissions.defaultMode` for edits

`permissions.allow` entries must name the scope they widen — `Bash(npm run:*)`, `Read(./src/**)`, `mcp__<server>`, `Edit(docs/**)`. A bare path or glob such as `"/home/ubuntu/.claude/**"` is **rejected and skipped** with `Invalid permission rule … Wildcard tool name … is not supported in allow rules`; the session still starts, so the only symptom is the capability you meant to grant staying absent. For an unattended run the useful lever is `"permissions": {"defaultMode": "acceptEdits"}`, which stops Write/Edit from prompting at all — a headless run has nobody to answer, so without it every edit fails with "you haven't granted it yet" and the agent falls back to `Bash` heredocs. Grant MCP servers by name (`mcp__devbot-tools`, …), grant edits by mode, and check the startup output for skipped-rule warnings rather than assuming a written rule took effect.
