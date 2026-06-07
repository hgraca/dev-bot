---
date: 2026-06-15
keywords: ["devbot", "external-modules", "config-rebuild", "encapsulation", "install"]
---

## Encapsulate external module config rebuild inside external-modules/install.sh

Moved the `_rebuild_external_module_config` logic from `bin/install.sh` into
`src/agentic/external-modules/install.sh` so all external module lifecycle
(config population from `external-modules.json` declarations + repo cloning)
lives in a single module. The config rebuild runs at the top of `main()`,
before the existing config-check and cloning loop, and respects disabled
modules. The `bin/up.sh` retains its own copy of the function as a safety
net for post-install module additions. Key convention: within module-level
`install.sh`, use `MODULE_DIR` for the shared merge script path and
`$dev_bot_root` (lowercase, set in `main()`) for scanning agentic modules
and locating the format-json tool.
