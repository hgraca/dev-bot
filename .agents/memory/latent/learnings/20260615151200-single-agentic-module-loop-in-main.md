---
date: 2026-06-15
keywords: ["devbot", "external-modules", "init.sh", "refactor", "main-loop"]
---

# Single agentic-module loop in main() with per-module function calls

`src/tools/external-modules/init.sh` is structured so that `main()` has one loop — over `src/agentic/*/` and `src/tools/*/` — and each iteration calls only `_process_agentic_module`, a function that delegates the disabled check, declaration lookup and per-module wiring/storage setup. Module entries from `.devbot.jsonc` are pre-read once into `MODULE_ENTRIES` (`name\x1furl\x1flocal_path\x1fpaths_json` per line) for O(n) lookup per declared name. Design principle: the `main()` loop contains only function calls — no conditionals, no variable assignments, no inline python.
