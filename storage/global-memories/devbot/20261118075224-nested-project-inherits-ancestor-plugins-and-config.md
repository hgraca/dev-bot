---
date: 2026-11-18
keywords: ["devbot", "nested-project", "plugins", "config", "ancestor"]
---

## A dev-bot project nested inside another inherits its plugins and config

opencode 2.x discovers configuration and plugins from the session directory and every ancestor. A dev-bot project nested inside another dev-bot project therefore loads the ancestor's `.opencode/plugins/` packages — `init.sh` deliberately retires the local shadow copies so the host does not fail them as Duplicate plugin ID — and **merges the ancestor's `opencode.jsonc`**, MCP servers, permissions and agents included. Consequences: the project's effective MCP palette is not its own file (one audit saw 10 extra disabled `datasources-*`/`aws-*` entries), and reinitialising the ancestor at a different dev-bot revision silently changes the nested project's hook code, because the ancestor's shims win. The ancestor packages are location-scoped and work correctly. Audit the effective config (`opencode2 debug config`, `opencode2 plugin list`), not only the project file. With no ancestor, init writes the three plugin packages locally and only the project's own config applies.
