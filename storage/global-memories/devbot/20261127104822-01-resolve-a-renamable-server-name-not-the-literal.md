---
date: 2026-11-27
keywords: ["devbot", "mcp", "server-name", "project-for-path"]
trigger-on: ["devbot-module-mcp-registration", "mcp-server-name-resolution"]
---

## A module server name that projects may rename must be resolved, not hardcoded

opencode stores MCP OAuth credentials per server _name_, so a project that needs a second account legitimately renames the server (`atlassian` → `atlassian-wedding`) while keeping the same endpoint; `devbot reinit` then re-registers the module's canonical name as a `disabled` stub beside it (`bin/init.sh:_register_module_mcp` skips only a key that already exists). Every gate that read the literal key reported Jira as disabled or absent, and "enable the MCP" pointed at the stub — the other account. The fix is `project-for-path --key atlassian_server`: match the server by the module's endpoint, prefer the enabled candidate, report `name: null` plus `candidates` when several entries compete or two are live, and report `error` (never `disabled`) for an entry whose flag is unreadable. Apply the same rule to every module whose server name is user-visible (`notion`, `context7`); a hardcoded name is only safe while nobody renames it.
