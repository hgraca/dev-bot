---
date: 2026-04-20
keywords: ["mcp", "server"]
---

## M-ARCH-035: Native execution preferred over Docker for MCP servers when possible

Git MCP server path mapping and ownership issues
Docker containers introduce path translation complexity and ownership mismatches. Native uvx execution avoids these issues while maintaining the same functionality. Consider Docker only when isolation is specifically required.
