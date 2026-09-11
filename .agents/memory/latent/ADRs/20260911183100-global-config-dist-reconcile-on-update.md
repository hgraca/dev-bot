---
date: 2026-09-11
keywords: ["devbot", "config", "reconcile", "dist", "update"]
see: ["ADRs/20260910141318-devbot-auto-update-version-reinit.md"]
---

## `devbot update` reconciles the global config against the dist schema

At the end of `devbot update`'s refresh block — reached only when the checkout actually moved, including `--auto` — the runtime `.devbot.global.jsonc` is reconciled against the shipped `.devbot.global.dist.jsonc` by `src/_shared/reconcile_global_config.py`: top-level properties present in dist but absent from runtime are added (copying dist's value and its trailing comment), runtime top-level properties absent from dist are removed, and properties present in both keep their runtime value and comment untouched. Nested objects are opaque (never reconciled), and there are no protected keys — dist is the schema. Comments are preserved via text surgery; the result is validated in a sibling temp file and swapped in with `os.replace`. Rationale: the runtime config is machine-owned and previously was only `cp`ed when absent, so an upgrade never gained new dist properties nor dropped retired ones. Accepted limitations: additions append at the end (object order is non-semantic), single-line/multi-property-per-line JSONC is unsupported (fails safe), input line endings normalise to LF, and an already-latest `devbot update` exits before the refresh block so it does not reconcile.
