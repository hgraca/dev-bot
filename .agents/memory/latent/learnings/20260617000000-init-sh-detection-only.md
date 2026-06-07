---
date: 2026-06-17
keywords: ["devbot", "init.sh", "module-structure", "separation-of-concerns"]
---

# Per-module init.sh: detection + info only; registration is centralized

Per-module `init.sh` files (under `src/agentic/<module>/init.sh`) should only detect whether the target project uses the module's technology and output informational messages about available tooling. They must NOT register MCP servers, plugins, or mutate any config files (opencode.jsonc, .mcp.json, etc.). All MCP server registration is handled centrally by `bin/init.sh` reading `mcp.opencode.json` from each module. External modules are also wired centrally from `external-modules.json`. This separation ensures registration logic stays in one place, avoids duplicated config-manipulation code across modules, and makes init.sh files simple, testable detection gateways. The pattern is: detect dependencies in target project → if match, output info about available MCP servers and external skills → return. The actual wiring happens elsewhere.
