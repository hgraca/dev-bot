---
date: 2026-09-17
keywords: ["devbot", "modules", "docker-compose", "signoz"]
trigger-on: ["module-gating", "devbot-up"]
---

## Disabled-module resolution must be passed the project dir, or a per-project enable is silently ignored

`_devbot_get_disabled_modules [project_dir]` computes the effective disabled set as *global ∘ project* — the project's `modules` map overrides the global one, so a project can enable a module that is `false` globally. With the argument omitted it reads the **global map alone**, so a per-project enable is dropped with no warning. Every caller that gates work on it must pass the project dir: `bin/up.sh` (both `_docker_up` and `_rebuild_external_module_config`) and `bin/down.sh` did not, so the compose file of any globally-disabled / project-enabled module was filtered out of the `docker compose` invocation and its container never started. `signoz` is configured exactly that way (`"signoz": false` in `.devbot.global.jsonc`, `"signoz": true` in a project's `.devbot.project.jsonc`), which is why the SigNoz MCP gateway stayed down and all `signoz_*` tools were missing while the harness booted cleanly — the module's `up.sh` readiness probe is non-fatal by design, so the failure is silent. Note also that such a compose service declares `restart: "no"` and will not return on its own, and `docker compose up -d --no-recreate` starts a stopped container without recreating it, so a stale container config survives until `devbot down && devbot up`.
