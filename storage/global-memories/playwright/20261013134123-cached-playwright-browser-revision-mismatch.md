---
date: 2026-10-13
keywords: ["playwright", "chrome-channel", "browser-revision", "npx-cache"]
trigger-on: ["playwright-launch-fails", "playwright-browser-not-installed"]
---

## Playwright revision drift: launch with `channel: "chrome"` instead of chasing the missing browser build

An ad-hoc Playwright (resolved from an `npx` cache rather than the project's own dependency) is coupled to one chromium revision, so when `~/.cache/ms-playwright` holds different revisions `chromium.launch()` dies with "Executable doesn't exist at …/chromium_headless_shell-<rev>/…" and tells you to run `npx playwright install`. When a system Chrome exists, the cheap fix is `chromium.launch({ channel: "chrome" })`: it drives `/usr/bin/google-chrome` and sidesteps the revision coupling entirely — no download, no cache surgery. Reach for `playwright install` only when the bundled build is genuinely required (verifying the exact browser Playwright ships). Related trap: a version bump of the Playwright package alone leaves the cache behind, which is how this is hit.
