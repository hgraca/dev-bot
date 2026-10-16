---
date: 2026-10-16
keywords: ["php", "intelephense", "lsp", "vendor", "memory"]
superseded_by: ["php/20261016221500-intelephense-config-only-via-lsp-configuration.md"]
---

## Intelephense reads `intelephense.config.json` (not `.intelephense.json`) in the workspace root

> **Superseded by** `php/20261016221500-intelephense-config-only-via-lsp-configuration.md` (2026-10-16) — Intelephense 1.16.5 does not read this file at all; config is only honoured via LSP `workspace/configuration`.

Intelephense's config file is `intelephense.config.json`, a direct child of the workspace folder, using flat dot-notation keys without the top-level `intelephense` wrapper (e.g. `"intelephense.files.exclude"`). It is only consulted when the LSP client doesn't support `workspace/didChangeConfiguration`/`workspace/configuration` (true for opencode). To cut memory: add `**/vendor/**` to `intelephense.files.exclude` — the default only excludes vendor _tests_ and nested vendor, so all of `vendor/` is deep-indexed otherwise (one instance was observed holding ~3.3 GB swapped indexing a Laravel vendor tree) — and add `"vendor"` to `intelephense.environment.includePaths` so symbols stay resolvable via a lightweight scan without full AST indexing. `intelephense.files.maxSize` caps per-file indexing (default 1000000 bytes). If you override `files.exclude`, re-declare the defaults (`**/.git/**`, `**/node_modules/**`, etc.) or they're silently lost.
