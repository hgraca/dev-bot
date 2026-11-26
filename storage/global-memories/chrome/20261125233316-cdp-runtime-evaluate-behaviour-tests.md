---
date: 2026-11-25
keywords: ["chrome", "cdp", "headless", "runtime-evaluate", "testing"]
aliases: ["test browser js without playwright", "stub the file picker", "devtools protocol"]
---

## Behaviour-test page JavaScript over CDP without puppeteer

When a project allows no browser test dependency and the browser MCP is off, page behaviour can still be exercised for real: launch `google-chrome --headless=new --remote-debugging-port=<port> --user-data-dir=<tmp> <url>`, poll `http://127.0.0.1:<port>/json/list` for the page target, and speak CDP over Node's built-in WebSocket. `Runtime.enable` plus `Runtime.evaluate` with `awaitPromise`, `returnByValue` and `userGesture` runs the page's own functions — a classic script puts top-level `function` declarations on `window` — and awaits their promises. Stub the platform API at the boundary (`window.showSaveFilePicker = async (opts) => { calls.push(opts); return fakeHandle }`) to verify `startIn`, `suggestedName` and write-back without a real picker; give each stubbed call its own slot, because a second click overwrites a single `captured` variable and reads as a failure of the first. Assert on the JSON returned from each evaluation and exit non-zero on a mismatch, so the run is a gate rather than a digest, and record `Runtime.consoleAPICalled` to fail on console errors.
