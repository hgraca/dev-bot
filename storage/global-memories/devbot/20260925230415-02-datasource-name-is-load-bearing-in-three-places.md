---
date: 2026-09-25
keywords: ["devbot", "datasources", "naming", "toolset", "mcp"]
trigger-on: ["devbot-datasources-name-mismatch"]
---

## A datasource name is load-bearing in three places, so a selection/catalogue mismatch yields a dead MCP

`src/agentic/datasources/init.sh` takes a project's selected datasource name verbatim as the harness server name (`datasources-<name>`) and as the URL path segment (`/mcp/<name>`), while `render_tools_yaml.py` derives the toolbox toolset name from the same global-catalogue key — three consumers of one string. If `.devbot.project.jsonc` selects a name the catalogue does not declare (seen: catalogue `mongo-dev-hotels`, project `mongo-hotels-dev`), the harness registers a server whose URL addresses a toolset that was never served, so the connection fails even with the gateway up and every other datasource healthy. `init.sh` only warns (`is selected but not declared`) and still writes the manifest, so the mismatch stays invisible until call time. Fix by renaming the project selection to the catalogue key — the catalogue's `<engine>-<env>-<db>` convention is the authority — then `devbot reinit` writes the new manifest, prunes the stale one and unregisters the old `opencode.jsonc` key; re-enable the new key, since a freshly emitted manifest ships `enabled: false`. Confirm with no network involved: `read_jsonc.py .devbot.global.jsonc datasources | available_catalogue.py | render_tools_yaml.py` (the network validator is skipped) prints the toolset name that will be served.
