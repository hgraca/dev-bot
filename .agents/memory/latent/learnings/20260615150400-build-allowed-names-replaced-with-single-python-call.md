---
date: 2026-06-15
keywords: ["devbot", "external-modules", "init.sh", "refactor", "python", "build_allowed_names"]
superseded_by: "project/20260615151200-single-agentic-module-loop-in-main.md"
---

# _build_allowed_names refactored to single python invocation

SUPERSEDED — see project/20260615151200-single-agentic-module-loop-in-main.md for the final design.

The `_build_allowed_names` function in `src/agentic/external-modules/init.sh` previously used a bash loop over `src/agentic/*/`, converted disabled modules JSON to newline-separated text via inline python, filtered disabled modules with `grep -Fxq`, and then extracted external module names from each enabled module's `external-modules.json` via a second inline python call. Refactored to a single python script that reads disabled JSON directly, iterates the directory, checks `if mod_name in disabled: continue`, and outputs allowed names. Commit: b890828.

This pattern — single python invocation that takes a JSON list (disabled modules), iterates the filesystem, and produces output — is the preferred approach for similar "iterate modules, skip disabled, process metadata" patterns.
