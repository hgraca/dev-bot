---
title: "External modules"
description: "Manage third-party module repos — clone, register, and wire them into projects."
tools: ["module"]
---

Add someone else's skills, agents or commands to a project the same way dev-bot's own modules are wired in.

## What it does

Provides the `devbot module` CLI and its lifecycle. An external module is a git repo (or a local directory) registered in `.devbot.global.jsonc` under `external_modules`; it is cloned into `vendor/`, mirrored under `storage/external-agentic-modules/`, and symlinked into each project's `.agents/<type>/<name>` exactly like a first-party module.

External modules follow the same anatomy as internal ones — they can ship agents, skills, commands, hooks, tools and memory bootstrap files — and the runtime treats them identically. The only difference is where they live on disk.

## Updating on start

A bare `devbot` start and `devbot up` both run this module's `up.sh` (unless the `external-modules` module itself is disabled), which checks every git-backed module against its remote and updates the ones that moved. The check is one `git ls-remote` per clone — refs only, no objects — run for all clones **in parallel**, so a start pays roughly one network round trip instead of one per module. A clone is fetched and hard-reset only when its tracked branch diverged; its storage mirror is re-rendered afterwards, so lifecycle scripts gained upstream are wired too. A configured module that is not cloned yet is cloned there.

The whole check runs **at most once per interval — 24 hours by default** — recorded in `storage/run/external-modules.checked`. A start inside the interval does no network work at all. `DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL` overrides the interval in seconds (`0` checks on every start, e.g. in CI). Only a complete check is recorded: if any remote could not be reached, the next start tries again rather than waiting out the interval. The stamp also records the configuration it covered, so a newly declared module, an edited URL or path, and a checkout or mirror that has gone missing are processed immediately instead of waiting out the interval — those repairs re-render locally and need no network call.

- Local-path modules have no remote and are skipped.
- A configured module that is not cloned yet is cloned here and wired into the project in the same start, so the first start is usable. Its own `up.sh`, if it ships one, first runs on the next start unless the mirror directory already existed before this one.
- Every configured path is validated against the **incoming** commit before the checkout moves. If one no longer exists upstream (a renamed or deleted directory, or a mapped memory file), the update is cancelled: the error is printed per path, the legacy checkout stays exactly as it was, and every symlink into it keeps resolving — nothing breaks and nothing is lost. The same validation refuses a first install whose repository does not provide the configured paths. Entries sharing one clone are validated together, so an update cannot silently drop an alias's path.
- `devbot install`, `devbot update` and `devbot module install` all run the same sync implementation, so the validation and cancellation above apply there too — a broken upstream commit cannot slip in through the update command. A completed install/update refreshes the start-time check stamp, so the next start needs no network check. A release-moving `devbot update` syncs them through its module update pass; an explicit `devbot update` that finds nothing to move syncs them before exiting. The start-time self-update (`--auto`) deliberately does not — the 24-hour check above owns that, so the interval still holds.
- The vendor path drops the host (`github.com/acme/repo` and `gitlab.com/acme/repo` both become `vendor/acme/repo`), so a second entry that maps onto an existing destination is skipped with a warning instead of being provisioned from the wrong checkout.
- A retained checkout must belong to the entry's URL: if `vendor/<owner>/<repo>` was cloned from a different repository (the path drops the host), the entry is skipped with a warning instead of being mirrored from the wrong code. Remove that checkout to switch repositories; ssh and https spellings of the same URL are treated as equal.
- `vendor/` is a managed checkout: an update hard-resets it, so local edits there are discarded. Register a fork, or the module as a `local_path`, to customize one.
- An unreachable remote (or a tracked branch deleted upstream) is a warning, not a start failure — the clone is left as it is. Each network call is capped at `DEV_BOT_FETCH_TIMEOUT` seconds (default 20).
- Concurrent starts serialize on a per-clone lock (`vendor/<owner>/<repo>.lock`), so two sessions cannot fetch and reset the same checkout at once. A lock that cannot be taken in `DEV_BOT_MODULE_UPDATE_LOCK_WAIT` seconds (default 120) warns and the check proceeds without it.
- Set the global `auto_update` to `false` to skip the check, the same switch that keeps the dev-bot install itself from updating on start. A pinned or offline machine then pays no network cost here.

Because this applies upstream code automatically, a module's own `up.sh` runs on the start that picks the update up — `bin/up.sh` runs service scripts. Its `init.sh` is different: init runs before `up.sh` and only when a reinit is triggered, so an upstream `init.sh` change takes effect on the next reinit (a config change, or a dev-bot update), not on the start that fetched it. `auto_update: false` is the gate for that trust decision; a module you do not want updating itself should be registered as a `local_path`.

## Configuration

Registration lives in `.devbot.global.jsonc`:

```jsonc
"external_modules": {
  "addyosmani": {
    "url": "https://github.com/addyosmani/agent-skills.git",
    "paths": {
      "agents": "agents",
      "skills": "skills",
      "memory": { "external/repo/path/instructions.md": "link/path/instructions.md" }
    }
  }
}
```

A string path value symlinks the whole directory; an object value symlinks each file at its exact destination (used for `memory/` bootstrap files); an omitted key means that module type is not wired.

## Disabled umbrellas

An umbrella module (e.g. `react`, `svelte`) can be turned off in the `modules` map. Disablement is **per-project and gates wiring only**: while the umbrella is off in a project, its external modules are not symlinked into that project's `.agents/<type>/<name>`.

Provisioning is deliberately enablement-independent. The `external_modules` store, the `vendor/` clones and the `storage/external-agentic-modules/` mirrors all live under the global dev-bot root and are shared by every registered project, so a module disabled in one project must not deny its external modules to the others:

- **Config** — `install.sh` and `bin/up.sh` merge every module's `external-modules.json` declarations regardless of enablement (`_devbot_rebuild_external_module_config`).
- **Clones** — `vendor/<owner>/<repo>` is never pruned, even when its umbrella is disabled.
- **Mirrors** — `bin/init.sh:_prune_orphaned_external_modules` removes a mirror only when **no** module declares it (enabled or disabled) and it is absent from `external_modules`. A declared name is always kept.

Remove an external module explicitly with `devbot module remove <name>`.

## See also

- [CLI commands](/modules/tools/devbot-cli) — the `devbot module` subcommands
- [Module Reference](/module-reference) — module anatomy
