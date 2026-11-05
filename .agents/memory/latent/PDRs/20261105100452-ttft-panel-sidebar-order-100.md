---
date: 2026-11-05
keywords: ["opencode", "ttft", "sidebar", "provider-ttft"]
aliases: ["lag widget", "time to first token panel"]
---

## The TTFT panel owns the order-100 sidebar row, shows one labelled per-session value

The provider-latency widget shows only **time-to-first-token**, as `TTFT 1.2s` (label plus value), in the sidebar row the built-in context block used (order 100) — not at the window edge, not in the sidebar footer. It is scoped to the active session: each session shows its own latest reading, and `TTFT -` before the first measurement. The stakeholder rejected three alternatives in order: an `app_bottom` bar at the window's bottom-right (wrong region), the sidebar footer (would displace `dir • branch`), and keeping the context block's tokens/percent/cost (unwanted noise). The consequence to remember: `internal:sidebar-context` must stay disabled in `plugin_enabled` — the panel occupies its slot rather than extending it, because `sidebar_content` panels are additive and cannot append to another plugin's row.
