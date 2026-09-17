---
date: 2026-09-17
keywords: ["datasources", "genai-toolbox", "red mcp", "lazy activation", "poller"]
---

# The datasources MCP goes red when its database is unreachable — and how to reproduce it

The `datasources` module renders `tools.yaml` from only the **usable** datasources — env-complete *and* TCP-reachable, decided by `available_catalogue.py` — and genai-toolbox treats an unreachable source as fatal. A DB outage therefore removes the toolset entirely: `/mcp/<name>` answers `{"code":-32600,"message":"toolset does not exist"}` and opencode paints that server red. A detached poller (`poller.sh`, `DATASOURCES_REFRESH_INTERVAL`, default 10s) re-renders whenever the usable set changes, and the toolbox hot-reloads the rewritten config **in place** (`cp`, not `mv`, because toolbox tracks the file by inode) — so the server side self-heals with no restart of anything. The client does not self-heal; that is the opencode MCP-client-cache behaviour recorded in the global store.

## Reproducing it

The **datasource** must be gone, not the gateway: every bare `devbot` start runs `bin/up.sh`, which resurrects the gateway container, so stopping `dev-bot-datasources-mcp` proves nothing. Either stop the database itself (the shared `shared-db-1` works), or point the datasource at a dead port by adding `"MYSQL_PORT"` to its `env` in `.devbot.global.jsonc` (gitignored runtime config — revert it afterwards). Note `datasources` never starts the database: the datasource is the developer's own service.

## Misleading empty-state message

`render_tools_yaml.py` prints `# No datasources configured in .devbot.global.jsonc.` whenever zero datasources are **usable** — which reads as "none configured" for a catalogue that is merely unreachable. Seen live during a DB outage, where the global config plainly did list one.
