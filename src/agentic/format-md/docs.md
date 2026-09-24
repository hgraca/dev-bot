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

## Configuration

No project configuration is required.

## See also

- [Format JSON](/modules/agentic/format-json)
- [Format YML](/modules/agentic/format-yml)
