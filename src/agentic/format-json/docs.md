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

A run happens only where the project declares prettier — a `.prettierrc*`, a `prettier.config.*`, or a `prettier` key in `package.json`. A project formatted by something else (Biome, say) is left alone. A missing prettier or node is never an error: the file is skipped with a warning.

`install.sh` installs prettier globally via npm when it is absent; `update.sh` installs it if missing, otherwise updates it.

## Configuration

The project must declare prettier — that declaration is the whole signal the hook uses. Nothing needs adding to `opencode.json`.

## See also

- [Format MD](/modules/agentic/format-md)
- [Format YML](/modules/agentic/format-yml)
