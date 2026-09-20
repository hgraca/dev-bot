---
date: 2026-09-16
keywords: ["opencode", "plugin", "engines", "npm", "silent-failure"]
trigger-on: ["opencode-plugin-dependency", "opencode-plugin-install"]
---

## opencode skips broken plugins silently — check `engines`, existence, and the platform before shipping a plugin name

A plugin listed in `opencode.json`'s `plugin` array can be a no-op with **no error anywhere**, which makes a wrong entry look like a UI problem. Three real cases from one evaluation pass: a package that **does not exist on npm at all** (404 — the project was a GitHub repo publishing differently-scoped packages under it), a plugin that installs and then does nothing because its `package.json` declares an incompatible host (`engines: { opencode: ">=2.0.0" }` against a 1.x host), and a plugin that is **macOS-only** (its source early-returns `if (platform() !== "darwin")`, marking every IDE "missing", and its README's Notes say so). The checks worth running before adding any third-party plugin name: `npm view <spec> engines exports version` (does it exist, what host does it need, does it export the entry the host loader wants — a TUI plugin needs a `./tui` export), and a grep of the installed source for a platform guard. Diagnose a silent skip from opencode's own log (`failed to load plugin` in `~/.local/share/opencode/log/opencode.log`), not from the UI. Related: local plugin files that fail to import are equally quiet, so make a plugin's first act write something observable.
