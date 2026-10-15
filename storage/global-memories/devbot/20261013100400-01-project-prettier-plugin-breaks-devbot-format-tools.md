---
date: 2026-10-13
keywords: ["devbot", "prettier", "format-md", "format-json"]
aliases: ["format-md failed Cannot find package prettier-plugin", "prettier plugin breaks devbot tools"]
trigger-on: ["devbot-format-tools", "prettier-config"]
---

## A project `.prettierrc.json` that declares `plugins` breaks devbot's `format-*` tools

The `format-md` / `format-json` / `format-yml` tools run a **globally installed** prettier, which resolves plugins relative to its own location — not the project. Declaring a config the global install cannot load fails the tool outright:

```
Error: Cannot find package 'prettier-plugin-tailwindcss' imported from /<project>/noop.js
```

That means adding a plugin (e.g. `prettier-plugin-tailwindcss`) to the project's shared `.prettierrc.json` silently breaks every `format-*` tool for that repo, even though `pnpm format` (project-local prettier) works fine. Keep the shared config plugin-free and pass plugins through the project's own script (`"format": "prettier --plugin=... --write ."`), or drop the plugin. Symptom to recognise: the tools fail on the _first_ file with a plugin-resolution error naming a file like `<project>/noop.js`.
