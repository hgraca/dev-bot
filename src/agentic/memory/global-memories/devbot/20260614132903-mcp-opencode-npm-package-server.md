---
date: 2026-06-14
keywords: ["devbot", "mcp", "opencode", "npm", "svelte"]
---

## MCP server from npm package: use npx in command array

When MCP server is published as an npm package (e.g. @sveltejs/mcp), auto-register via mcp.opencode.json with `"type": "local"` and `"command": ["npx", "-y", "@sveltejs/mcp"]`. The `-y` flag prevents interactive prompts. No need to install globally — npx resolves and caches automatically. Verify package exists: `npm view @<org>/<pkg>`. Add noinstall.sh or pre.sh check for Node.js >= 18 since npx requires it.
