---
date: 2026-10-16
keywords: ["opencode", "opencode-tabs", "session-tabs", "kv-persistence", "tui-plugin"]
aliases: ["tabs revive", "closed tab reappears", "tab resurrection", "session tabs plugin"]
trigger-on: ["opencode-tui-plugin", "opencode-tabs", "tui-plugin-persistence"]
---

## opencode-tabs (the pinned TUI session-tabs plugin) reopens tabs you close

The `opencode-tabs` TUI plugin (third-party npm package; dev-bot pins `opencode-tabs@0.3.0` in `src/harnesses/opencode/tui.dist.jsonc`) has no durable "closed" marker: it stores the open-tab list in opencode's **global** kv at `opencode-tabs:tabs:v1:<projectID>:<cwd-relative-path>` — a single last-writer-wins JSON file shared by every opencode process — and it re-admits a tab whenever the TUI's route points at a session whose tab is missing. Closing a tab only removes it from that list; the session itself is never deleted, so any later navigation back to it (or another opencode instance rewriting the same key) recreates the tab, and it persists into the next restore. `devbot -c` / `opencode -c` ("continue the last session") forces exactly such a route at startup, so a closed tab for the resumed session comes back on the next launch. opencode upstream carries the same defect in its built-in tab system (issue #41394, "closing a tab active on another client re-opens it", self-diagnosed as last-writer-wins JSON state; fix underway in PR #44715), and 0.3.0 is still the latest release — there is no fixed version to pin. Diagnose by watching the kv key: it is read once at startup (each session validated, 404 → dropped), then written back on every tab change, so a key still holding a closed session's id is the evidence.
