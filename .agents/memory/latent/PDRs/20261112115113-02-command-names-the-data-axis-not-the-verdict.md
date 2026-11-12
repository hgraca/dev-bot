---
date: 2026-11-12
keywords: ["slash-command", "naming", "devbot-stats", "devbot-audit"]
---

## A command is named for the data axis it owns, not the verdict it prints

`/devbot:stats` kept its name over the credible alternative `health`, because `devbot:audit` already
owns "is the harness healthy" — config correctness, MCP connections, logs. Two commands in the same
semantic slot make `/devbot:health` versus `/devbot:audit` a coin flip. `stats` marks the axis this
command owns, usage over a window, and mirrors the CLI (`/devbot:stats` runs `devbot stats`), so
provenance is obvious; the verdict it prints (working / improvable / broken) lives in the description
and body, not the name. `usage`, `doctor` and `diagnose` were rejected for the same overlap or for
hiding the "working well" third of the answer.
