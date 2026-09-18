---
date: 2026-09-17
keywords: ["devbot", "dist-config", "plugin-reconciliation", "seed-once"]
see: ["ADRs/20260908213000-mcp-manifest-consolidation.md"]
---

## Existing projects converge on the dists' full plugin set; removals are hand edits

A dist-backed config is written once, when the file is absent, and is user-owned thereafter — so an entry added to a dist afterwards never reaches an existing project, and one removed from a dist never leaves. Both happened in practice: `opencode-pty` was added and every seeded project lacked the dependency its PTY panel calls, and `opencode-dir-tree-tui` was dropped while `core` kept running it.

**Decision:** `init.sh` reconciles **every** plugin the two dists ship (mirrored in `harnesses/opencode/required-plugins.jsonc`, with a test asserting each dist entry appears there) into an already-seeded `opencode.jsonc` / `.opencode/tui.json` on every init and reinit. An earlier, narrower scope — only the plugins dev-bot's own features break without — was rejected by the stakeholder as leaving `opencode-tabs` absent from every existing project: a divergence, not a protection.

**Boundaries, all deliberate:** additions only, because "remove anything the dist does not list" would delete plugins a project added itself, so something no longer shipped is removed by hand; and no other dist keys are ever reconciled (`agent` models, `permission`, `watcher.ignore`, `lsp` are per-project customisation and reconciling them would fight the user). The reconciliation is the only automated write to these configs after seeding.
