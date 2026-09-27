---
date: 2026-09-27
keywords: ["playwright", "mcp", "browser", "install-browser"]
trigger-on: ["playwright-mcp-npm-fallback", "playwright-browser-missing"]
---

## The @playwright/mcp npm package does not install a browser

Installing `@playwright/mcp` globally gives you the server, not a browser. The
docker-absent fallback that runs the npm binary with `--browser chromium` then
fails at first use with "Browser … is not installed; expected executable at
~/.cache/ms-playwright/chromium-<rev>/…". Install it with
`npx -y @playwright/mcp@<version> install-browser chrome-for-testing` (the
command the package itself exposes), which is idempotent when the build is
present.

Watch the revision coupling: the chromium revision is tied to the @playwright/mcp
version, so a version drift between an image bake and a module/global install
leaves the server looking for a revision the cache lacks. Keep the bake and the
pin in lockstep, and ensure the browser step runs even when the package is already
at the pinned version — an early "already installed" return is exactly how this is
missed.
