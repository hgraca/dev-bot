---
layout: page
title: Session Capture
description: Auto-promotes learnings to memory before context compaction.
nav_section: docs
---

The `remember-session` skill captures what was learned during a session and routes it to the knowledge vault — so the next session starts smarter.

## How it works

- **Post-commit hook**: after each `git commit`, a trigger file is written
- **Session idle**: when the session goes quiet, `remember-session` fires
- **Learning routing**: findings are categorized:
    - Product decisions → `memory/latent/PDRs/`
    - Architecture decisions → `memory/latent/ADRs/`
    - Gotchas → `memory/latent/global/<tech>/` or `memory/latent/learnings/`
- **Watermark tracking**: only new learnings since the last capture are processed

## Manual trigger

Say "wrap up", "remember session", or "capture session" to trigger it manually.

## See also

- [QMD](/tools/qmd) — knowledge vault search
- [Memory Management](/module-reference) — vault structure and conventions
