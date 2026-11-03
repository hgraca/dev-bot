---
title: "Format MD"
description: "Markdown formatting via prettier."
skills: ["format-md"]
hooks: ["format-md"]
tools: ["format-md"]
---

Auto-formats markdown files on save via prettier. Aligns table columns, normalizes heading spacing, and formats code fences.

## How it works

The `on-file_edited` hook fires when any `.md` file is saved. The plugin runs prettier and writes the formatted output back.

A run uses the project's prettier configuration when it declares one — a `.prettierrc*`, a `prettier.config.*`, or a `prettier` key in `package.json`. A project that declares none is formatted with the config dev-bot ships (`src/_shared/prettier.default.json`, currently prettier's own defaults), so `--check` reports instead of failing with `no prettier config`. The flip side is that a project formatted by something else and without a prettier config (Biome, say) is now formatted too; disable this module (`"format-md": false` under `modules` in `.devbot.project.jsonc`) to opt out. A missing prettier or node is never an error: the file is skipped with a warning. An edit is never failed by formatting.

`install.sh` installs prettier globally via npm when it is absent; `update.sh` installs it if missing, otherwise updates it.

## Configuration

A project that declares prettier gets its own settings, apart from the parser and print width dev-bot pins on the command line, and its `.prettierignore` is honoured — the `.agents/` workspace is always formatted. Without a declaration dev-bot's defaults apply. Nothing needs adding to `opencode.json`.

## See also

- [Format JSON](/modules/agentic/format-json)
- [Format YML](/modules/agentic/format-yml)
