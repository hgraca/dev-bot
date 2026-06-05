---
date: 2026-04-22
keywords: ["graphify", "graph"]
---

## Config key backfill via `_INI_DEFAULTS` array

When adding new config keys to `devbot.ini`, add them to both `src/tools/opencode/init.sh` (for new projects) and the `_INI_DEFAULTS` array in `bin/update.sh` (for existing projects). The update script discovers all projects via `storage/graphify/*/.project-path`, checks each ini file for missing keys, and appends defaults. This pattern scales to any number of future config keys — one array entry per key.
