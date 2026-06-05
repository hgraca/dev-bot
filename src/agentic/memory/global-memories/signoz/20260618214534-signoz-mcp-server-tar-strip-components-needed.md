---
date: 2026-06-18
keywords: ["signoz", "mcp-server", "tar", "strip-components", "download"]
trigger-on: ["signoz-mcp-server-download", "signoz-binary-install", "signoz-tar-strip"]
---

## Signoz MCP server GitHub release archive requires --strip-components=2 when extracting

The SigNoz MCP server GitHub release archive has structure `signoz-mcp-server_linux_amd64/bin/signoz-mcp-server` — a top-level platform directory wrapping a `bin/` subdirectory containing the binary. Without `--strip-components=2`, the binary lands at `storage/signoz/bin/signoz-mcp-server_linux_amd64/bin/signoz-mcp-server` instead of the expected `storage/signoz/bin/signoz-mcp-server`. Both `tar xz` (curl pipe) and `tar xzf` (wget tempfile) paths need the flag. The `--strip-components=2` removes the top-level directory AND the `bin/` subdirectory from tar entries, placing the binary directly at the destination.
