---
date: 2026-09-22
keywords: ["chrome", "user-data-dir", "SingletonLock", "headless", "concurrent"]
trigger-on: ["chromium-shared-profile", "per-instance-browser-agent", "chrome-user-data-dir"]
---

## Two Chromium processes cannot share a `--user-data-dir` — the second aborts with exit 21

Chromium enforces a per-profile singleton lock: launching a second browser against the same `--user-data-dir` fails immediately rather than attaching to the running instance, with

```
ERROR:chrome/browser/process_singleton_posix.cc:347] Failed to create <dir>/SingletonLock: File exists (17)
ERROR:chrome/app/chrome_main_delegate.cc:520] ... Aborting now to avoid profile corruption.
```

and exit status 21. This bites any tool that spawns one browser per agent or session instance: `chrome-devtools-mcp` defaults to a single shared profile (`$HOME/.cache/chrome-devtools-mcp/chrome-profile`), so a second concurrent instance's browser never starts at all — the per-instance server is defeated by the shared profile. Pass `--isolated` (a temporary per-instance profile, removed when the browser closes) or an explicit per-instance `--userDataDir`. `--headless` does not exempt you: the singleton check applies there too. Reproduced on Playwright's bundled Chromium 1234 with `--headless --no-sandbox`: first instance served CDP on its port (HTTP 200), the second exited 21 with the messages above.
