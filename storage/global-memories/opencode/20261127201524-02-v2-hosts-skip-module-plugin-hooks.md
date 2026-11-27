---
date: 2026-11-27
keywords: ["opencode", "opencode-v2", "plugin-hook", "session.idle", "hooks.json"]
aliases: ["module hooks do not run on 2.x", "required-plugins.jsonc", "ctx.session.context envelope"]
---

## A v2 OpenCode host runs no module `plugin:` hooks

A module `hooks.json` entry declared with `plugin: "<path>"` is dispatched by the v1 adapter only; the v2 adapter logs `skipping N manifest-declared V1 plugin hook(s)` and never calls it, so that behaviour is inert on OpenCode 2.x while every suite stays green. The v2 route is a plugin package: a directory with `index.ts` exporting `Plugin.define({ id, setup })`, linked into `.opencode/plugins/` (auto-loaded) and declared in the harness's `required-plugins.jsonc`, or the next init retires it as a stale package. Inside that context the shapes differ from v1: events arrive as `{ type, data }` rather than `{ properties }`, and `ctx.session.context({ sessionID })` answers a client envelope `{ data: [...] }` whose entries are storage-shaped — assistant text under `content[]`, the tool name at `name` — not the `{ info, parts }` message a v1 plugin receives. Subscribe without a type filter and skip other `event.type`s yourself, as the harness's own adapter does: a host that ignores the `types` option would otherwise hand you every event.
