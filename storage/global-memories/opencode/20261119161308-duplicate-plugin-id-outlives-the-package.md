---
date: 2026-11-19
keywords: ["opencode", "plugin", "duplicate-plugin-id", "nested-project", "restart"]
aliases: ["devbot-skill-name-resolver failed", "plugin shows failed in the TUI", "duplicate registration"]
trigger-on: ["opencode-plugin-registry", "nested-project-plugins"]
---

## A duplicate plugin id keeps failing until the host restarts, even after the package is deleted

opencode v2 auto-loads every `.opencode/plugins/` package from the project **and every ancestor**, so two dev-bot projects where one sits inside the other register the same ids twice. The host keeps the first and marks the second `failed` with `Duplicate plugin ID: <id>` — visible as "&lt;plugin&gt; failed, local" in the plugin list — while the first copy stays `active` and works.

The trap is that deleting the duplicate package does not clear the entry: the registration was made at load time, so the API and the TUI keep reporting the dead copy as `failed` long after the directory is gone, which reads like the fix did nothing. Confirm the disk is clean (`ls .opencode/plugins/`) and restart the harness to drop the stale registration. Fixing the cause means making sure only the outermost project writes the shared packages — a nested project must defer to the ancestor's copy, and the two inits must not run concurrently, or both write one.
