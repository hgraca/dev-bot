---
date: 2026-11-26
keywords: ["opencode", "tui", "plugin", "setup", "subscribe"]
aliases: ["Invalid V2 TUI plugin module", "v2 tui plugin ctx", "plugin async event stream"]
---

## opencode v2's TUI plugin contract is `{ id, setup(ctx) }` over an async event stream

A `./tui` part is validated as a default export of `{ id: string, setup(ctx) }`; any other shape is rejected at startup with `Invalid V2 TUI plugin module` and shows up as a failed plugin. The v1 shape (`{ id, tui(api) }`) is not accepted, and neither is the pre-2.3 ctx: `kv`, `slots` and v1's `event.on(type, handler)` are gone.

Events arrive as an **async iterable** — `for await (const event of ctx.event.subscribe({ signal }))`, dispatched on `event.type`, with the payload under **`data`**. v1 used `properties`, so code written against v1 makes every v2 event look empty. Pass an `AbortController`'s signal, or the stream outlives the plugin.

Cleanup is **the function `setup` returns**, not a registered disposer: `return () => { controller.abort(); clearInterval(poll) }`. A plugin that starts a timer or a subscription and returns nothing leaks for the life of the TUI.

`ctx.state.session.get(id)` still exists and returns the session, but treat the whole ctx as something to feature-detect — 2.3 changed its surface once already, and a missing member should make the plugin inert rather than a failed plugin at startup.
