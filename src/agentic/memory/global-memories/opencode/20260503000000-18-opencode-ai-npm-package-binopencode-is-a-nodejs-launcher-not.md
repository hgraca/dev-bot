---
date: 2026-05-03
keywords: ["opencode", "tool"]
---

## `opencode-ai` npm package `bin/opencode` is a Node.js launcher, not the binary

The npm package's `bin/opencode` is a `#!/usr/bin/env node` script that searches `node_modules/` for platform-specific packages (e.g. `opencode-linux-x64`). If the platform package isn't installed (common with global installs), it errors: "It seems that your package manager failed to install the right version". The actual binary lives at `~/.opencode/bin/opencode` (downloaded by postinstall). When building from source, place the binary there directly.
