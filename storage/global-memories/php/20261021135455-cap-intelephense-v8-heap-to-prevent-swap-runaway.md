---
date: 2026-10-21
keywords: ["php", "intelephense", "node", "v8", "memory"]
---

## Cap Intelephense's V8 heap with --max-old-space-size to prevent swap runaway

Beyond pinning a leak-fixed release (see `php/20261016221500-intelephense-config-only-via-lsp-configuration.md`), the hard guard against a runaway Intelephense is a V8 heap cap: launch it with `NODE_OPTIONS=--max-old-space-size=2048` (a single instance was observed holding ~3.3 GB of swap while indexing). Node uses the LAST occurrence of the flag, so append it after any inherited options rather than prepending, or an inherited `--max-old-space-size` overrides the cap. In the dev-bot setup this lives in the LSP wrapper `dev-bot/src/harnesses/opencode/lsp/intelephense.sh`, which also resolves the binary by search order (`dev-bot/storage/intelephense` first, then opencode's cache) — so to find the version actually running, read the wrapper and the process cmdline, not `~/.cache/opencode/packages/intelephense`.
