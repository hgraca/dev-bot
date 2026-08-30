---
date: 2026-06-15
keywords: ["devbot", "init.sh", "disabled_modules", "external-modules"]
---

## init.sh external-modules wiring bypassed disabled_modules gate

`_wire_external_modules()` in `bin/init.sh` called `src/agentic/external-modules/init.sh` directly with no `disabled_modules` check — so even when `external-modules` was listed in `disabled_modules`, its init.sh still ran. Root cause: init.sh had 4 separate loops through agentic modules (init.sh, MCP registration, memory linking, external wiring) each re-parsing disabled_modules independently, and the external wiring was a standalone function call outside all module-skipping logic. Fixed by consolidating into a single unified loop through `src/agentic/*/` with disabled_modules parsed once and one `continue` gating all init actions per module (commit 561cbca).
