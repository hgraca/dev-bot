---
date: 2026-09-22
keywords: ["devbot", "dev-tools", "plugin", "github-actions", "sync"]
trigger-on: ["dev-tools-plugin-sync"]
---

## dev-tools ships only what `plugin.sh` declares — an undeclared file stays repo-local

A consuming repo receives dev-tools content solely through the composer package's `src/Bash/plugin.sh`. That script copies a fixed, flag-gated list of `src/GitHub/Workflows/*`, `src/GitHub/actions/*`, `src/Bash/*` and the Makefile; anything absent from it — e.g. `get-e/core`'s `.github/actions/php-setup-dependencies/action.yml`, which carries core-only pnpm/protobuf steps — is repo-local and is never delivered, refreshed or overwritten by a dev-tools release. Two consequences: a dev-tools version bump cannot make such a local CI file obsolete, and declared actions are protected unevenly — `dev-tools-action/action.yml` is copied **only when absent**, so local customisations (core's extra allowed namespaces) survive every update, while `redis-cluster/action.yml` is copied unconditionally and overwritten. Read `plugin.sh` before assuming a `.github/` file is dev-tools-managed, or that a release will fix it.
