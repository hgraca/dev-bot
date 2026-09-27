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

An umbrella module (e.g. `react`, `svelte`) can be turned off in the `modules` map. Disabling it stops its external modules from being wired into `.agents/<type>/<name>` and stops their declarations being re-added to the config. On reinit the **storage mirror** of a name declared only by a disabled umbrella is pruned (`bin/init.sh:_prune_orphaned_external_modules`).

An existing **vendor clone** is deliberately kept: `vendor/<owner>/<repo>` is never pruned, even when its umbrella is disabled. The clone is gitignored and cheap, and re-enabling is then instant. Remove it by hand if you want the disk back.

## See also

- [CLI commands](/modules/tools/devbot-cli) — the `devbot module` subcommands
- [Module Reference](/module-reference) — module anatomy
