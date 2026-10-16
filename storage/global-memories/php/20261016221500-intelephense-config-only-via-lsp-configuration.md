---
date: 2026-10-16
keywords: ["php", "intelephense", "lsp", "vendor"]
supersedes: ["php/20261016171147-intelephense-config-file-and-memory.md"]
---

## Intelephense reads config only via LSP workspace/configuration

Intelephense 1.16.5 does **not** read a project-root `intelephense.config.json` — the filename appears zero times in the packaged code, so a config file placed in the workspace is inert. Configuration arrives only through LSP `workspace/configuration` (or `workspace/didChangeConfiguration`): opencode advertises `capabilities.workspace.configuration: true` and answers section `"intelephense"` from `server.initialization["intelephense"]`, so a settings override must ride on opencode's `lsp` config `initialization`, never a file. Two further traps. (1) `intelephense.environment.includePaths` is re-indexed with the *same* exclude globs but `cwd = the includePath`, so `**/vendor/**` cannot match there — an `includePaths: ["vendor"]` alongside a vendor exclude re-adds everything the exclude removed (measured on a fixture: default = 439 files, exclude-only = 138, exclude + includePaths = 439, i.e. identical to default). (2) Because the same exclude list also runs at the workspace root, a bare `**/tests/**` drops the *project's* own tests too — vendor-internal slices must use `vendor/`-segment patterns (`**/vendor/**/tests/**`). To cut Intelephense memory, pin a newer release (1.18.5 fixes a memory leak from old syntax-tree fragments accumulating while editing) rather than trusting a config file.
