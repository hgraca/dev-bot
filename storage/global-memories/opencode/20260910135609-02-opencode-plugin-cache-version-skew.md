---
date: 2026-09-10
keywords: ["opencode", "plugin-cache", "codebase-index", "version-skew"]
trigger-on: ["opencode-plugin-cache-stale"]
---

## opencode's plugin cache can lag the npx-resolved MCP server version

opencode installs a plugin declared as `"opencode-codebase-index"` into `~/.cache/opencode/packages/opencode-codebase-index@latest/node_modules/opencode-codebase-index` and caches it by `@latest` without re-resolving. That cache held 0.22.3 (expects index schema versions 4/1) while the MCP server launched via `npx -y -p opencode-codebase-index ...` resolved to 0.27.0 (expects 9/2). Two package instances expecting different schema versions can ping-pong the index: one writes its migration metadata, the other marks the index "migration-required". When codebase-index retrieval fails after an upgrade, check both the plugin cache version and the npx cache version (`~/.npm/_npx/*/node_modules/opencode-codebase-index/package.json`) and align them (refresh the plugin cache / reinstall) before blaming the index.
