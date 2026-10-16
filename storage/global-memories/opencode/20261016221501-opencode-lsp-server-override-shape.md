---
date: 2026-10-16
keywords: ["opencode", "lsp", "intelephense", "initialization"]
---

## opencode LSP: a `lsp.<id>` override replaces spawn and initialization

Setting `lsp` to an object in `opencode.jsonc` does not merely tweak a built-in server — each named entry reuses the built-in's `root` (e.g. the composer.json-based root for PHP) but **replaces its `spawn` and `initialization` wholesale**. The override shape therefore *requires* `command` (an array), and any `initialization` the built-in set is lost unless it is re-declared. Two gotchas: the built-in PHP server id is the literal `"php intelephense"` — a key of `"intelephense"` names a *custom* server and silently does nothing; and the `command` is spawned via cross-spawn against `PATH`, so a binary opencode keeps outside PATH (its own `node_modules/.bin/intelephense`) needs a resolving wrapper. opencode answers LSP `workspace/configuration` from `server.initialization`, and Intelephense requests section `"intelephense"`, so settings go at `initialization.intelephense`. All other built-ins stay enabled: opencode registers every built-in first, then applies the named overrides.
