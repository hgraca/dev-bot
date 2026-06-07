---
date: 2026-06-12
keywords: ["devbot", "documentation", "modules", "docs", "external-modules", "config"]
---

## Module doc refinements — memory/, external parity, and config format

Expanded `docs/module.md` with three additions to the consolidated module reference: (1) added `memory/` to the agentic module anatomy tree — documented as holding bootstrap files symlinked into `.agents/memory/` for external modules; (2) clarified that external modules follow the same anatomy and provide the same capabilities as internal modules (only difference is disk location: `vendor/` vs `src/agentic/`); (3) added a new Configuration format section explaining the `.devbot.jsonc` `modules` key format, `paths` key semantics (string = directory symlink, object = file-level symlink with exact destination), and the expanded storage layout including `storage/external-agentic-modules/<name>/` and `.agents/memory/` paths.
