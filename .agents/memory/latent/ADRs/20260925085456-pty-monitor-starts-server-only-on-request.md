---
date: 2026-09-25
keywords: ["pty-monitor", "opencode", "tui-plugin", "startup"]
---

## The PTY monitor never starts the PTY server as a side effect of loading

`src/harnesses/opencode/pty-monitor/` used to bootstrap `opencode-pty`'s HTTP server from its plugin factory on every opencode start: create a throwaway session, run `pty-show-server-url`, scrape the origin, delete the session. That held the TUI on its "Loading plugins…" screen for ~6.6 s per start (74 bootstrap sessions in the log), because opencode awaits every TUI plugin factory with no timeout and gates that overlay on the promise chain. The factory now returns immediately after wiring, the first refresh is detached, and loading resolves the origin with a side-effect-free `/proc` scan only. Starting the server is an explicit user action — the `/pty-monitor` slash command ("start or refresh") or clicking the sidebar header to expand the panel — and both triggers clear the backoff, so neither can leave the other a dead end. A deferred explicit request is remembered (`bootstrapPending`) and run when the in-flight refresh finishes, so a single click is never dropped, and every HTTP probe is bounded by a 2 s `AbortSignal.timeout`. Background worth keeping: the ~6 s was never the plugin's own I/O (the PTY static assets read in 43 ms and 94 skill files in 303 ms) — it was the command round-trip waiting on server-side boot.
