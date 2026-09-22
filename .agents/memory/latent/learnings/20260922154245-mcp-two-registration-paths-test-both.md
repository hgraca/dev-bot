---
date: 2026-09-22
keywords: ["mcp", "devbot", "testing", "mcp_translate", "claudecode"]
---

# MCP servers register through two independent paths — a test on one does not support a claim about both

A module's MCP servers reach a harness config by two routes that share no code:

- **canonical** — `src/agentic/<module>/mcp.json`, translated by `src/_shared/mcp_translate.py`, merged by `bin/init.sh::_register_module_mcp` (opencode) and by `_wire_mcp`'s first loop (claudecode).
- **dynamic** — `.opencode/<name>.mcp.json` / `.claude/<name>.mcp.json`, written at init time by modules whose values only exist at runtime (`jetbrains`, `datasources`), then merged by `_register_dynamic_mcps` (opencode) and by `_wire_mcp`'s **second** loop — which copies the entry **verbatim** apart from its `enabled` gate.

The trap: a claim that spans both paths is not tested by a test that exercises one. A change to `_wire_mcp` was claimed to stop `enabled` reaching `.mcp.json`, and the new claudecode test asserted `chrome-devtools`, `playwright` and `signoz` — all canonical. It passed while `jetbrains` and every `datasources-<name>` entry still carried the key, because the dynamic loop copies the whole entry. Review reproduced the leak; the fix strips the key _and_ the test now names both dynamic owners.

Checklist item for any manifest-driven harness change: name one module from each path in the test (a canonical one and a dynamic one), and assert the value, not presence. The same duality applies to env-var gating (`mcp_env_refs.py` is shape-aware for exactly this reason), docker guards, and `_devbot_manifest_owner_disabled`.
