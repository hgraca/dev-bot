---
date: 2026-08-22
keywords: ["devbot", "hooks", "migration", "dead-code"]
trigger-on: ["tool-migration", "stale-hook-import"]
---

## Migrating a tool (.js → .sh) leaves stale hook imports that break silently

When a module's tool is migrated (e.g. `agent-communication`'s `tools/agent-communication.js` became `tools/agent-communication.sh`), the opencode hook that still `import`s the old module breaks — the hook is dead code, failing only at load time with no obvious signal. The `agent-communication` test file even documented the breakage in a comment ("the hook will fail to load at runtime until the JS module is restored") but the dead hook lingered until a migration sweep removed it. When migrating a tool's implementation, grep for stale references in hooks and tests and remove or repoint them — a test comment noting the breakage is not a fix.
