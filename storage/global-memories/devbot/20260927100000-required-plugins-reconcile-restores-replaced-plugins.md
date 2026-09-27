---
date: 2026-09-27
keywords: ["devbot", "required-plugins", "reconcile", "plugin-double-load"]
trigger-on: ["devbot-required-plugins-reconcile", "plugin-double-load"]
---

## The harness's `required-plugins` reconcile is additions-only, so it silently restores a plugin you replaced

`_ensure_required_plugins` in `src/harnesses/opencode/init.sh` reconciles an existing project config *up* to `required-plugins.jsonc` and never removes anything — deliberately, because "remove whatever the dist does not list" would delete plugins a project added itself. So while testing a locally-wired replacement for a pinned plugin, any `devbot init`/`reinit` puts the pinned entry back alongside it: `opencode-pty@0.3.6` reappeared in `opencode.jsonc` next to the fork's `./storage/opencode-pty/index.ts`, and `./tui-plugins/pty-monitor/index.ts` reappeared in `.opencode/tui.json` next to the fork's TUI entry. Both consequences are easy to misread as defects in the replacement. The visible one is a duplicate: two TUI plugins each register a sidebar panel. The confusing one is that two *server* plugin instances load into one process, each with its own module graph, so one instance's tools and the other's web server see different state — `pty_list` reported a running session while the same process's `GET /api/sessions` reported zero, which looks exactly like a plugin bug and is not (one instance owned the sessions and ran no HTTP server; the other served the origin record and the endpoint the UI reads). Diagnose by checking the active config for a leftover pinned entry before suspecting the replacement, and remember the permanent fix is to update `required-plugins.jsonc` (and the dists) rather than the project config, since a project-level removal is exactly what the reconcile undoes.
