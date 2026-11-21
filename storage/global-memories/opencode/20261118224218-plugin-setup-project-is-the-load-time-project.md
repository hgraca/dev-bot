---
date: 2026-11-18
keywords: ["opencode", "plugin-hook", "ctx.location", "session-directory", "project-canonical"]
trigger-on: ["opencode-plugin-setup", "project-root-resolution"]
---

## A plugin's `setup(ctx)` project is the load-time project, not the session's

In opencode 2.x a plugin package discovered under an ancestor's `.opencode/plugins/` is loaded for the project whose config declared it, so `ctx.location.project.canonical` inside `setup(ctx)` answers **that** project — not the directory of the session it later serves. Observed on a dev-bot project nested in its polyrepo: `mcp-sync` logged `loaded for /…/Get-e` while the session ran in `/…/Get-e/dev-bot`, and its project-scoped writes landed in the ancestor's `opencode.jsonc` while the nested project's log stayed 0 bytes. `on-hooks` in the same run resolved the nested project, so the two packages disagree and neither the log nor a missing tool surfaces it. Rule: a plugin that writes project-scoped state must take `ctx.location.directory` as the only target and treat `project.canonical` as a signal for hosts that omit `directory` — and must **not** fall back to it when the directory fails validation, because falling back across scope re-creates the very bug the validation exists to prevent (a nested project then writes to its ancestor). A session that is not the expected project has nothing to sync; doing nothing is correct. Log both inputs once at setup so the mismatch diagnoses itself.
