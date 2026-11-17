---
title: "Playwright"
description: "Drive a real browser from an agent — end-to-end testing and UI reproduction."
mcps:
  playwright: "Browser automation and end-to-end testing"
---

Drive a real browser: navigate, interact, and assert — for end-to-end tests, or to reproduce a UI bug the way a user hits it.

## What it does

Wires the Playwright MCP server (`mcp/playwright`) into the harness.

Launch is **hybrid**: where Docker is available it runs the server in a container (`docker run --rm -i -v "$PWD:$PWD:z" -w "$PWD" --label dev-bot.mcp=playwright mcp/playwright`), and otherwise it falls back to a locally installed `@playwright/mcp`. The local binary is resolved by explicit npm-prefix paths rather than the bare name on `PATH`, so a stale system binary can never win.

The container gets the project bind-mounted at the same absolute path, because the server validates upload and screenshot paths against the host project root and resolves filenames against its own working directory: without the mount, `browser_file_upload` rejects every host file and a screenshot `filename` fails with `ENOENT`. The mount is read-write on purpose — an element or full-page screenshot may target any path in the repo, and a read-only project mount with a writable logs subdirectory would break those. The exposure is therefore "a process in this container can rewrite the project", and starting the harness with its working directory at `$HOME` would mount the home directory; both follow from the working directory, not from this module. The `:z` suffix relabels the mount for SELinux hosts (ignored elsewhere). The image runs as uid 1000, which is what makes the mounted files writable on a typical developer machine; on a host with a different uid, screenshot and output writes fail with `EACCES` — the fix is to run the container with `--user "$(id -u):$(id -g)"` and a writable `HOME`, which is not enabled by default because that combination is unverified against the image's browser profile.

The server allows uploads only from its output directory or its working directory, so `browser_file_upload` of a file outside the project (e.g. `~/Downloads`) is refused by design; `--allow-unrestricted-file-access` exists but is deliberately not used. Both launch paths pass `--output-dir .agents/logs/playwright-mcp` so generated snapshots, screenshots and console logs land in the gitignored logs directory instead of the default `./.playwright-mcp` in the repo root. The Docker Hub image publishes only `latest`, so the docker path runs whatever that tag resolves to and need not match the `@playwright/mcp` version pinned in `versions.env`; the npm fallback is the pinned one.

## Configuration

`install.sh` installs the pinned `@playwright/mcp` version recorded in `versions.env`; `devbot update` resolves the newest version and rewrites the pin. Registered on `devbot init` when the module is enabled. If the package is missing, the launch fails loudly with `FATAL: @playwright/mcp not installed — run 'devbot install' (module playwright)`.

## See also

- [Chrome DevTools](/modules/agentic/chrome-devtools) — the inspection sibling
- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
