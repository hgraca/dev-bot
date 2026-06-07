---
date: 2026-06-18
keywords: ["signoz", "tar", "shell", "install"]
---

# GitHub release tar archives may have nested directories — verify extraction layout

The SigNoz MCP server releases a tar.gz with structure `signoz-mcp-server_linux_amd64/bin/signoz-mcp-server`.
Without `--strip-components=2`, the binary lands at `storage/signoz/bin/signoz-mcp-server_linux_amd64/bin/signoz-mcp-server`
instead of the expected `storage/signoz/bin/signoz-mcp-server`. Both install.sh existence checks and init.sh
execution look for the flat path, so the binary appears missing even after successful download.

Fix: always inspect the archive layout before writing extraction commands. When the archive wraps binaries in
platform-specific directories, use `tar xz --strip-components=N` to flatten. For SigNoz, N=2 strips both the
top-level directory and the inner `bin/` directory. Same principle applies to any module download script.
