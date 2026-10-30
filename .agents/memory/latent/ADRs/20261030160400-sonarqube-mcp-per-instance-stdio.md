---
date: 2026-10-30
keywords: ["devbot", "sonarqube", "mcp", "stdio", "gateway"]
---

# SonarQube MCP Runs Per-Instance Over stdio

The `sonarqube` module launches the official `sonarsource/sonarqube-mcp` container over stdio per harness instance instead of running a machine-wide compose gateway. The server carries a per-user token, a per-instance SonarQube URL/org (Cloud EU/US or self-hosted Server) and a per-project workspace mount, so it is not machine-global/stateless; and the MCP entry ships `enabled: false`, so a disabled server must start no process at all — a module-gated gateway would run a container even while the MCP is off. The launcher passes the token with `-e VAR` (name only) so it never enters argv, mounts the project read-only by default, and pulls the pinned image lazily with `--pull=missing`. `docs/mcp-config.md` states that the gateway pattern is for machine-global, stateless servers; per-identity servers (`aws`, `chrome-devtools`, `playwright`, `sonarqube`) stay stdio.
