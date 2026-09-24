---
date: 2026-09-24
keywords: ["devbot", "docs", "gather-module-docs", "front-matter", "ci-paths"]
---

# Invariants to keep when changing the module-docs generator

`src/agentic/docs/tools/gather-module-docs.py` is the build-time generator behind the docs site. Four things bite when it changes:

- **One capability source.** The module's declared front-matter manifest drives the page Contents, the capability strip, the index `Contains` column and the aggregate tables. Deriving the aggregate counts separately made one module show `1 tool` in the index and `T=4` in `module-reference`, because the derived scan also counted gitignored `__pycache__` and the generator's own `templates/` directory — an environment-dependent count.
- **The declared manifests must be complete.** Once the manifest is the single source, anything a module forgets to declare is silently hidden. Four modules had under-declared tools that live in a subdirectory (`use-case-map`, `lint-k8s`, `refactor`, `search-memories`/`reindex-memories`) and those tools vanished from the site until the manifests were completed.
- **The front-matter parser supports a small subset** — scalars, `[a, b]` flow lists, one level of `name: purpose` nesting. YAML block scalars and block sequences are rejected with an error rather than mis-read: `description: >-` used to parse as the literal `>-` and still satisfied the required-description check.
- **`on.push.paths` must follow the source of truth.** Moving docs into `src/**/docs.md` left the Pages workflow triggering on `docs/**` alone, so editing a module's docs never deployed it. Adding a source of truth means adding it to the workflow's path filter.

Escape table cells (`|` → `\|`) in every generated table, not only the aggregate ones — the index and the page Contents were each breakable by a pipe in a description.
