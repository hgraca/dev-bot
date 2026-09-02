---
date: 2026-09-02
keywords: ["external-modules", "devbot", "namespaced", "recursive", "additive-paths"]
---

## External module model — full intent and open design branches

Product decisions (2026-09-02 session, all confirmed by the stakeholder): external modules in `.devbot.global.jsonc:external_modules` may be git-sourced (`url`) or local (`path`), with `path` winning when both are set and never being cloned/copied to `vendor/`; the local source is never modified. Names are namespaced identities: `<org>/<repo>` for git (derived from url), `local/<folder>` for local (CLI `--name` overrides only the folder). Users must be able to register git repos directly and have them wired (config-only entries are wired, not just declared ones). External modules form a dependency graph: any external module root (vendor clone or local path) may ship its own `external-modules.json` and declare further modules, resolved to closure by `devbot install` with a visited-set against cycles. Entries carry provenance so pruning is safe: `_declared_by` (union of declaring modules, set by merges with `--owner`) vs `_user_added` (CLI registrations); an entry is pruned only when not user-added and every declarer is disabled or gone, which chains removal of transitive children when a parent module disappears.

Open branches for the NEXT session (not yet designed/built):

- **Additive paths (stakeholder requirement)**: one entry per repo — a repo like `mindrally/skills` currently appears as several logical entries (mindrally-react/nextjs/best-practices) selecting different subdirs, causing duplicated config/storage/links/update passes over one clone. Required: keep the `org/repo` naming, make a `paths` type accept SEVERAL paths (arrays), give each path its own `.agents` namespace under the repo entry, and make removal match per repo/path (drop one path when several remain; drop the whole repo entry+clone only when the last path goes).
- Monorepo-subdir naming for disabled react/svelte declarations (they were left short-keyed since three entries share the url `github.com/mindrally/skills` and would collide under org/repo).

See: ADRs/20260902140000-external-modules-architecture.md
