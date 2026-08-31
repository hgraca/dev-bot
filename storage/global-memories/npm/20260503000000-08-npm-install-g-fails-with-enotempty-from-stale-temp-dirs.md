---
date: 2026-05-03
keywords: ["npm", "install", "enotempty"]
---

## `npm install -g` fails with ENOTEMPTY from stale temp dirs

`npm install -g opencode-ai` fails with `ENOTEMPTY: directory not empty, rename ... -> .opencode-ai-XXXXX` when a previous interrupted install left temp directories in the global node_modules. Fix: `rm -rf "$(npm prefix -g)/lib/node_modules/.opencode-ai-"*` before retrying. Added automatic cleanup to `update.sh`.
