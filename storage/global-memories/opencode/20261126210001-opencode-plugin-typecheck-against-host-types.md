---
date: 2026-11-26
keywords: ["opencode", "tui plugin", "typescript", "typecheck", "plugin context"]
aliases: ["typecheck a TUI plugin", "pin the host plugin types", "Context assignability", "plugin fixture types"]
---

## Typecheck a TUI plugin against the pinned host package, not a hand-written slice

To make an OpenCode TUI plugin's host surface a compile-time contract: add `@opencode/plugin@<host version>` **and** `@opencode/client@<same version>` as devDependencies (the pair must move together) plus `typescript`; a `tsc --noEmit -p` config with `skipLibCheck: true` resolves `Context` without installing its optional peers (electron/OpenTUI) — verified with `--omit=peer`. Derive the slice the plugin reads instead of hand-writing it: `data.session` may stay a structural `{get}`, but `data.on` must be the host's exact generic (`Context["data"]["on"]`) or `(ctx: Context): TuiCtx => ctx` fails on parameter variance, and `ui.router` should be `Pick<Context["ui"]["router"], "current">`. That whole-context assignment checks shapes _when present_ but not presence of optional slice members, so add explicit presence assertions (`(ctx) => ctx.data.session`) and read each event field off the inferred handler (`on("session.renamed", (e) => e.data.title)`) to pin payload fields. Type the test double against the slice, and type its event emitter with the host event map's **full** `data` type — wrapping it in `Partial` silently erases requiredness and lets the double emit shapes the host never produces. Including the tests in the config needs `@types/bun` in `types`; `node:child_process` imports need `@types/node`.
