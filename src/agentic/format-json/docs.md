---
title: "Format JSON"
description: "JSON/JSONC formatting via prettier."
skills: ["format-json"]
hooks: ["format-json"]
tools: ["format-json"]
---

Auto-formats `.json` and `.jsonc` files on save via prettier with 2-space indentation. Handles comments and trailing commas natively.

## How it works

The `on-file_edited` hook fires when a `.json`/`.jsonc` file is saved, runs prettier, and writes the formatted output back.

A run uses the project's prettier configuration when it declares one — a `.prettierrc*`, a `prettier.config.*`, or a `prettier` key in `package.json`. A project that declares none is formatted with the config dev-bot ships (`src/_shared/prettier.default.json`, currently prettier's own defaults), so `--check` reports instead of failing with `no prettier config`. The flip side is that a project formatted by something else and without a prettier config (Biome, say) is now formatted too; disable this module (`"format-json": false` under `modules` in `.devbot.project.jsonc`) to opt out. A missing prettier or node is never an error: the file is skipped with a warning.

`--force` is still accepted for compatibility with `devbot reinit`/`up`, which format `opencode.jsonc` and `.devbot.global.jsonc`; it no longer changes behaviour.

`install.sh` installs prettier globally via npm when it is absent; `update.sh` installs it if missing, otherwise updates it.

## Configuration

A project that declares prettier gets its own settings, apart from the parser, print width and ignore path dev-bot pins on the command line; without a declaration dev-bot's defaults apply. Nothing needs adding to `opencode.json`.

## See also

- [Format MD](/modules/agentic/format-md)
- [Format YML](/modules/agentic/format-yml)
