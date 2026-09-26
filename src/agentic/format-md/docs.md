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

A run happens only where the project declares prettier — a `.prettierrc*`, a `prettier.config.*`, or a `prettier` key in `package.json`. A project formatted by something else (Biome, say) is left alone, as is one with no formatter declared. A missing prettier or node is never an error: the file is skipped with a warning, so an edit is never failed by formatting.

`install.sh` installs prettier globally via npm when it is absent; `update.sh` installs it if missing, otherwise updates it.

## Configuration

The project must declare prettier — that declaration is the whole signal the hook uses. Nothing needs adding to `opencode.json`.

## See also

- [Format JSON](/modules/agentic/format-json)
- [Format YML](/modules/agentic/format-yml)
