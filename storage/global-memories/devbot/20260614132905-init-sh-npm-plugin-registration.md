---
date: 2026-06-14
keywords: ["devbot", "init.sh", "opencode", "plugin", "npm"]
---

## init.sh registers npm-published opencode plugins via _upsert_opencode_plugin

The @sveltejs/opencode plugin is an npm package name, not a local TS file path. When registering such plugins in init.sh, pass the npm package name string directly to _upsert_opencode_plugin — it inserts into the target project's opencode.jsonc `plugin` array. Use a Python one-liner to check if already registered (parse JSON, check list membership, return SKIP/ADD) before calling _upsert_opencode_plugin for idempotence.
