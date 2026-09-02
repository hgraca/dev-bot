---
date: 2026-09-02
keywords: ["devbot", "external-modules", "module add", "config-only", "wiring", "init.sh"]
---

# External modules: CLI-registered modules need explicit wiring; declarations gate init

After the revert to the origin named-import model, the external-modules flow
had a split-brain: `src/tools/external-modules/init.sh` (run by reinit) wired
only names declared in internal `external-modules.json` files into the project
`.agents` dir, while the legacy `tools/module.sh` CLI wired config entries into
`.opencode/`. A `devbot module add`-ed module was therefore never usable after
reinit (audit-29 FAIL-1), git-url adds targeted the dev-bot install dir's
`.opencode` instead of registered projects (FAIL-2 — `_discover_projects()`
only searched inside `DEV_BOT_ROOT`), and `remove` left `.agents` links behind
(NOTE-1).

Fixes now in `init.sh`/`module.sh`: init.sh runs a config-only pass wiring
every remaining `external_modules` entry (skipping names declared by ANY
module — enabled ones are wired by the declared loop, disabled react/svelte
must stay off), `_discover_projects()` also reads the global config's
`projects` registry, and `_unwire_module` cleans `.agents` links too. Pattern
to remember: in the named-import model, "declared" and "registered" are
different things — init.sh gates on declarations, the CLI registers into the
config; wiring must bridge both.
