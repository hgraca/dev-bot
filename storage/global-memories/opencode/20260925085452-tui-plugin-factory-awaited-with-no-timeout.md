---
date: 2026-09-25
keywords: ["opencode", "tui-plugin", "plugin-factory", "startup"]
trigger-on: ["opencode-tui-plugin", "opencode-plugin-factory"]
---

## A TUI plugin factory is awaited with no timeout, so it must never block

opencode's TUI plugin host (`TuiPluginRuntime.start`, decompiled from the bundled runtime inside the `opencode` binary) activates plugins sequentially — `for (const p of plugins) await activate(p)` — and `activate` does a plain `await plugin(api)` with **no timeout**; the timeout wrapper exists only in the dispose path. The TUI's "Loading plugins…" overlay is gated on that same promise chain resolving, so any plugin factory that does blocking I/O holds the entire TUI on that screen, and a factory that never resolves hangs startup outright with no watchdog. Observed live: a sidebar plugin whose factory awaited a session-bootstrapping call stalled every opencode start for ~6.6 s (74 bootstraps in the log). Rule: a TUI plugin factory must register its slots and commands and return; defer any I/O to a detached call or a timer.
