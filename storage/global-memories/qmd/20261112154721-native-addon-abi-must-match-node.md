---
date: 2026-11-12
keywords: ["qmd", "better-sqlite3", "NODE_MODULE_VERSION", "npm-rebuild", "node"]
aliases: ["ABI mismatch", "ERR_DLOPEN_FAILED", "native addon rebuild"]
trigger-on: ["native-addon-abi-mismatch"]
---

## A native addon must be built for the Node ABI that loads it

`ERR_DLOPEN_FAILED` with "was compiled against a different Node.js version using NODE_MODULE_VERSION 127. This version of Node.js requires NODE_MODULE_VERSION 147" means a native addon — here `better-sqlite3` bundled under `@tobilu/qmd` — was built for Node 22 while the runtime is Node 26. `127` and `147` are ABI numbers, not versions, so there is nothing to "upgrade to": the binary must match the loader. Fix by rebuilding against the running Node, from the addon's own directory: `cd <package>/node_modules/better-sqlite3 && npm rebuild` (fetches a matching prebuilt or compiles; needs python3 and a C++ toolchain), then prove it with `node -e "const D=require('<path>'); new D(':memory:')"`. Pinning Node 22 for that tool is the alternative. A global npm install freezes the ABI of whichever Node built it, so a Node major upgrade silently breaks such tools until they are rebuilt — check this before blaming the caller's code when a working tool starts failing after a Node bump.
