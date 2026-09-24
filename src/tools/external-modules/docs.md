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

## See also

- [CLI commands](/modules/tools/devbot-cli) — the `devbot module` subcommands
- [Module Reference](/module-reference) — module anatomy
