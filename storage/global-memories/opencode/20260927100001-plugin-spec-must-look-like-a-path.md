---
date: 2026-09-27
keywords: ["opencode", "plugin", "config", "specifier"]
trigger-on: ["opencode-plugin-path-specifier"]
---

## An opencode plugin spec that does not look like a path is treated as an npm package — and a miss is silent

A `plugin` entry in `opencode.json`/`opencode.jsonc` must *look* like a path or opencode resolves it as an npm package name: `".opencode/plugins/on-hooks.ts"` and `"./storage/opencode-pty/index.ts"` load as files, but `"storage/opencode-pty/index.ts"` (no leading `./`) is parsed as a package called `storage`, fails to resolve, and is **skipped without any error** — no log line, no TUI warning, nothing in the plugin list. The symptom is indirect and actively misleading: the other half of the same feature loads fine (the TUI plugin was demonstrably running — it created its bootstrap session and rendered its panel), while every contribution of the *server* half was missing, so the only clue was `Command not found: pty-show-server-url` printed beside a long "available commands" list. Always give a file plugin a `./`, `../`, `/` or `file:` prefix, and when one surface of a two-surface plugin works while the other contributes nothing, check the spec's shape before the code — a bare relative-looking path is the cheapest thing to rule out first.
