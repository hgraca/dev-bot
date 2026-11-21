---
date: 2026-11-19
keywords: ["mcp", "vite", "tidewave", "plugin"]
trigger-on: ["vite-mcp-server", "wiring-a-framework-mcp"]
---

## A Vite MCP server is a plugin inside the dev server, not a process a manifest can launch

Unlike Next.js — whose `next-devtools-mcp` is a standalone stdio server that attaches to a running
dev server — every Vite MCP lives *inside* the app: `vite-plugin-mcp` (antfu, `/__mcp`),
`vite-mcp` (broisnischal, `/__mcp`) and Tidewave (`tidewave/vite-plugin`, `/tidewave/mcp`) are
plugins the project adds to `vite.config.ts`. A harness manifest can therefore only be a **client**
pointing an http transport at the dev server's port; it cannot launch one, and nothing answers until
the consumer installs the plugin and serves on that port. Tidewave is the worst trap of the set
because its repository README documents a `npx tidewave mcp` stdio mode with a `--prefix` flag, and
the published `tidewave@0.10.0` CLI registers only `install`, `docs` and `source` — the README is
ahead of the tarball. Check a CLI's real subcommands against the published package (`npx -y
<package> --help`) before wiring it into a manifest, never against the repo's main-branch docs.
