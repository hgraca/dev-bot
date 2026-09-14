---
date: 2026-09-14
keywords: ["devbot", "mcp", "architecture", "resources", "runtime-slimdown", "docker-compose"]
see: ["ADRs/20260908213000-mcp-manifest-consolidation.md", "ADRs/20260822224308-harness-agnostic-module-init.md"]
---

## Gate heavy MCP servers per project; share stateless ones machine-wide via docker compose

devbot boots one harness instance per project, and each instance spawns its **own full set of MCP servers**. Measured on one machine with four concurrent instances (2026-09-14): ~5.8 GB RSS total across the four harness trees, ~1.78 GB of it in the MCP server copies alone. The same stateless servers (`mdctx`, `signoz`, `codebase-memory`, `svelte`) were rebuilt four times; only per-project/per-instance servers genuinely differ per instance. Tool-schema cost measured via real `tools/list` handshakes: chrome-devtools ~6.5k tokens, codebase-memory ~5.9k, playwright ~3.5k — a session running all local module servers starts with ~17.5k tokens of MCP schemas before any conversation.

**Decision — a dual-layer model.**

**Layer 1: per-project gating (the default, config-only).** A project pays only for the servers it uses. Module enablement stays the canonical gate (ADR `20260908213000` module-gate policy unchanged); a project opts out of _heavy per-instance servers_ (chrome-devtools, playwright, graphify, signoz…) by **disabling the server's module** (`disabled_modules`) — decided 2026-09-14: module-level only, no new per-server config key. opencode's runtime `mcp.<name>.enabled: false` is honored (verified: config is load-once, not hot-reloaded) and remains the local escape hatch for disabling an inherited server without unregistering it. Measured schema costs and the lever are documented in `docs/mcp-config.md`.

**Layer 2: shared machine-wide MCP layer via docker compose.** Servers proven stateless and machine-global run **once** per machine as compose services; harnesses connect over http (MCP streamable-http / SSE) instead of N stdio copies. This follows the existing `src/tools/{ollama,litellm}/docker-compose.yml` pattern auto-discovered by `devbot up`/`down`. Initial candidates by T0.3 classification, in rollout order:

| server            | why shareable                                                                                                |
| ----------------- | ------------------------------------------------------------------------------------------------------------ |
| `signoz`          | fixed org endpoint + env token; stateless client; heaviest stdio cost (83–94 MB/instance)                    |
| `svelte`          | `@sveltejs/mcp` docs server, no project binding                                                              |
| `mdctx`           | index root is dev-bot's machine-global `storage/global-memories`                                             |
| `codebase-memory` | tools take `repo_path` per call (`index_repository`/`list_projects`); already forks a shared internal daemon |

Explicitly **not** shared (stay per-instance stdio): `chrome-devtools`, `playwright` (browser context per session), `devbot-tools`, `graphify`, `codebase-index` (`--project .`), `react/next-devtools` (project dev-server binding). `context7` and `websearch` are already remote.

**Accepted trade-offs.** Requirement: each shared server must support an http transport (or run stdio behind a tiny gateway); a server that can't stays per-instance rather than forcing the design. A single daemon port per machine needs collision-safe defaults (lesson: codebase-memory's fixed port 9749 collided across instances). Token schemas of shared servers are still injected per session — layer 2 saves RAM/CPU, not tokens; the token cost is owned by layer 1 (gating) and T2.2.

**Follow-up work.** (1) Standardize versions pinning across enabled binaries (done for chrome-devtools/playwright in T1.2; extend to svelte/next-devtools when enabled). (2) Layer 1 is documentation-only — module-level disablement is the gate (no new config key). (3) T3.3 — compose file + http wiring per shared server, rollout signoz first; verify transport support per server before moving it. (4) T4.1 — a `devbot` runtime-footprint report to keep these numbers measurable.
