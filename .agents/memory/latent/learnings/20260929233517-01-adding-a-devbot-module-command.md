---
date: 2026-09-29
keywords: ["devbot", "command", "commands-farm", "devbot-cli", "module"]
---

# Adding a command to a dev-bot module takes three things, not one

A slash command is not wired by dropping a file into the module. Three pieces:

1. **The file** — `src/agentic/<module>/commands/<name>.md` with `name: devbot:<name>` front matter. `_link_commands` (`src/tools/devbot-cli/functions.sh`) reads the frontmatter `name`, strips the `devbot:` prefix, and symlinks the file to `<devbot_dir>/commands/devbot/<bare>.md`. The bare filename is deliberate: opencode reads the frontmatter `name` while claudecode derives `<dir>:<file>` from the path, so the `devbot/` category plus a bare filename gives both harnesses the same slash command.
2. **The manifest** — a `commands: ["<name>"]` entry in the module's `docs.md` front matter. The capability manifest is the single source for the module page, the `/modules` index, `_data/modules.yml` and the six aggregate pages, so a command missing there is invisible site-wide.
3. **The farm** — `bash src/tools/devbot-cli/init.sh <project>` (its `_link_modules` iterates `src/agentic/*/` and `src/tools/*/`, calling `_link_agents`/`_link_commands`/`_link_skills`/`_link_tools`). `devbot init` runs it in the normal lifecycle; a bare `bats`-style test of the file proves nothing about wiring.

## The trap

`devbot list commands` reads `src/agentic/*/commands/*.md` **directly** with a glob — so a new command appears in the listing before any farm rebuild. The listing is not evidence the harness will find it; check for the symlink under `<devbot_dir>/commands/devbot/` instead.
