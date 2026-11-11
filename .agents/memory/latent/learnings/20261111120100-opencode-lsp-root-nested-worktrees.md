---
date: 2026-11-11
keywords: ["opencode", "lsp", "worktree", "NearestRoot"]
---

# OpenCode LSP roots a custom server at the launch directory, not the file's project

## The trap

OpenCode's `lsp` config has no `root`/`rootUri` option. Built-in server ids use
`NearestRoot([...markers...])` (walk up from the file, stopping at `ctx.directory`), but a **custom
server id that is not a built-in gets `root = ctx.directory`** — the directory OpenCode was launched
on, with no marker gating. DevBot's PHP server is such a custom entry (`php intelephense` →
`lsp/intelephense.sh`), so with OpenCode launched on the main checkout it roots there and resolves
`App\` through the main checkout's `app/`. Files in a linked worktree
(`<project>/.agents/worktrees/<slug>`) then get diagnostics from the wrong copy of the code (e.g.
"Unknown named argument" after a signature change that only exists in the worktree).

## Local mitigation

`opencode.jsonc` excludes `**/.agents/worktrees/**` from the PHP server's `initialization` file list
(the entry is reconciled by `harnesses/opencode/reset.sh`), and in-container static analysis is the
authority for worktree code.

## Upstream

Filed https://github.com/anomalyco/opencode/issues/63292 (per-server `root`). The V2 LSP port tracker
https://github.com/anomalyco/opencode/issues/38528 says "preserve location scoping" and does not add
a root option, so the behaviour would carry into v2. The closed v1 issue #48785 documents the
custom-id/`ctx.directory` mechanism and asked for an explicit `root`/`global` field.
