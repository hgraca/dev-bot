---
date: 2026-10-07
keywords: ["devbot", "install", "modules", "lifecycle", "enablement"]
aliases: ["install all modules", "machine-wide module lifecycle", "modules map gates init only"]
see: ["ADRs/20260927172101-external-modules-enablement-independent.md"]
trigger-on: ["devbot-module-install"]
---

## Machine-wide module lifecycle is enablement-independent; only init/up/list gate

`devbot install`/`update`/`uninstall` and the prereq pass run **every** module's script regardless of the `modules` map: `_run_module_script` gained a leading `--all` and `_install_modules`/`_update_modules`/`_uninstall_modules` pass it, while `_run_module_prereqs` dropped its gate. Rationale: a module's install assets and CLI are machine-wide, but the `modules` map is per-project and `install` has no project dir, so gating install on the map (effectively global-only) left a module enabled in exactly one project unprovisioned — its MCP wired by `init` while its skills/CLI were never fetched, and `graphify/init.sh` even hard-fails without its CLI. This generalises the external-modules rule (`20260927172101`) to internal modules and mirrors `down.sh` (`_run_service_scripts --all`: removal is machine-wide). Enablement now gates only per-project wiring — `init` and `up` — and the default `devbot list` view (`--all` overrides). Trade-off accepted: modules disabled everywhere (`aws`, `ollama`, `litellm`, `sentry`, `signoz`, `react`, `svelte`) still provision on every machine. Fixed in commit `34e0e324`.
