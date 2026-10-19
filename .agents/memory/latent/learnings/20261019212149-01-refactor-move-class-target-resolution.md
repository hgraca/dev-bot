---
date: 2026-10-19
keywords: ["refactor", "move-class", "move-target", "psr-4", "rector"]
aliases: ["php class move half-move", "move --kind class", "unresolvable move target"]
---

# PHP `move-class` must resolve exactly one target before Rector runs

The earlier note blaming a missing `"declaration": "class"` in the `move-class` spec is a red herring. `_declaration_re(name, "")` falls through to the class-like regex (`class|interface|trait|enum`), so the empty kind already matches a class declaration; adding the key changes nothing.

The real defect was resolution: `move-target` keyed only on the short name. When the declaration was absent, ambiguous, in a classmap root, or mapped to a colliding/non-mirroring PSR-4 path, it emitted nothing — and the plugin still ran `RenameClassRector`, repointing references at an FQCN the move never delivered.

## What the fix enforces

- Resolve candidates by the qualified `from` FQCN first, else `--file`; dedupe by `(FQCN, normalized path)` so overlapping roots (`src`, `src/Sub`) are not mistaken for ambiguity.
- Refuse missing/ambiguous targets, a changed short name (`move-class` keeps the name; use `rename-class`), an existing destination, and every PSR-4 base location that would shadow the chosen target.
- For `qualify` ops (`rename-class`), pass the file-selected namespace explicitly; the plugin must not put a FQCN into `from` because `resolve_namespace` expects the short name. For non-qualify ops (`move-class`), replace the request's short `from` with the resolved FQCN so Rector repoints references.
- `move-target` exits non-zero on refusal; `plugin.sh` aborts before `_run_steps` and rolls the scope snapshot back.

Covered by `src/agentic/refactor/tests/refactor_php_ops_tests.bats` (unit `move-target` cases plus CLI end-to-end tests).
