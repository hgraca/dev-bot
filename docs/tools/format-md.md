---
layout: page
title: Format MD
description: Markdown formatting via prettier.
nav_section: docs
---

Auto-formats markdown files on save via prettier. Aligns table columns, normalizes heading spacing, and formats code fences.

## How it works

The `on-file_edited` hook fires when any `.md` file is saved. The plugin runs prettier and writes the formatted output back.

## See also

- [Format JSON](/tools/format-json)
- [Format YML](/tools/format-yml)
