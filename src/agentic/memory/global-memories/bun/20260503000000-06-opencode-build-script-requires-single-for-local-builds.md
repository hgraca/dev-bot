---
date: 2026-05-03
keywords: ["bun"]
---

## opencode build script requires `--single` for local builds

The opencode `script/build.ts` builds binaries for ALL platforms (linux, darwin, win32) by default, downloading cross-platform native deps (e.g. `lightningcss-darwin-x64` on Linux) which fails. Pass `--single` to build only for current platform. Also pass `--skip-install` if deps are already installed. Syntax: `bun run --cwd .../packages/opencode build -- --single --skip-install`. Fixed in commit 95c86c2.
