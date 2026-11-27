---
date: 2026-11-26
keywords: ["opencode", "tui plugin", "plugin context", "session.renamed", "ui.router"]
aliases: ["opencode 2.x TUI plugin API", "ctx.state is gone", "plugin ctx data ui", "session.updated missing"]
supersedes: ["opencode/20261126073210-01-v2-tui-plugin-contract.md"]
---

## OpenCode 2.x TUI plugins get `data` and `ui`, never v1's `state`/`route`/`event`

A TUI plugin's `setup(ctx)` in OpenCode 2.x receives a context of `{options, location, app, renderer, client, data, attention, theme, themeMode, markdown, keymap, storage, ui}` — there is no `state`, `route`, or `event` member (v1's TUI API). The shown session comes from `ui.router.current()` → `{type: "session", sessionID}` (or `home`/`plugin`), sessions from `data.session.get(id)` / `data.session.root(id)` (both `SessionInfo` with optional `title`/`parentID`), and events from `data.on(type, handler)`, where the handler receives the event object itself (`event.data`) — `data.listen` takes one handler for every event, wrapped as `{details}`. The `V2Event` union has `session.created`, `session.renamed` (`data: {sessionID, title}` — the generated title and every manual rename both arrive here) and `session.deleted`, but **no `session.updated`** (that name is the server's durable log event) and no route-change event at all, so following a session switch needs a timer reading `ui.router.current()`. The TUI part is the plugin package's `./tui` export; the loader validates `{id, setup}` and cleanup is the disposer `setup` returns. A plugin written from the server-plugin docs (`ctx.event.subscribe({signal})`) fails silently here — check `dist/tui/context.d.ts`, not the server API, before wiring one.
