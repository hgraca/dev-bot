---
date: 2026-06-16
keywords: ["devbot", "init.sh", "disabled_modules"]
---

## bin/init.sh parses disabled_modules before tool init writes config

In `bin/init.sh` `main()`, `disabled_modules` is parsed at function entry (lines 267-275) — but `tools/devbot/init.sh` writes `.ai/devbot/devbot.jsonc` (with project-specific disabled modules like `signoz`, `svelte` from `.devbot.project.dist.jsonc`) during the tool init loop. The subsequent agentic modules loop uses the stale pre-write parse, so modules that should be skipped run their init anyway. Fix: add a re-parse of `disabled_modules` between the tool init loop's `done` and the agentic modules loop to pick up config changes written by tool init scripts. Both parses are needed — the early parse for external module loop and the re-parse for the agentic modules loop.
