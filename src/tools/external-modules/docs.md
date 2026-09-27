---
title: "External modules"
description: "Manage third-party module repos — clone, register, and wire them into projects."
tools: ["module"]
---

Add someone else's skills, agents or commands to a project the same way dev-bot's own modules are wired in.

## What it does

Provides the `devbot module` CLI and its lifecycle. An external module is a git repo (or a local directory) registered in `.devbot.global.jsonc` under `external_modules`; it is cloned into `vendor/`, mirrored under `storage/external-agentic-modules/`, and symlinked into each project's `.agents/<type>/<name>` exactly like a first-party module.

External modules follow the same anatomy as internal ones — they can ship agents, skills, commands, hooks, tools and memory bootstrap files — and the runtime treats them identically. The only difference is where they live on disk.

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

- **Config** — `install.sh` and `up.sh` merge every module's `external-modules.json` declarations regardless of enablement (`_devbot_rebuild_external_module_config`).
- **Clones** — `vendor/<owner>/<repo>` is never pruned, even when its umbrella is disabled.
- **Mirrors** — `bin/init.sh:_prune_orphaned_external_modules` removes a mirror only when **no** module declares it (enabled or disabled) and it is absent from `external_modules`. A declared name is always kept.

Remove an external module explicitly with `devbot module remove <name>`.

## See also

- [CLI commands](/modules/tools/devbot-cli) — the `devbot module` subcommands
- [Module Reference](/module-reference) — module anatomy
