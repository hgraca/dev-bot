---
date: 2026-11-27
keywords: ["javascript", "axios", "interceptor", "xsrf"]
trigger-on: ["axios-response-interceptor", "csrf-replay"]
---

## An axios interceptor branch that resolves silently breaks its callers

Two traps, both hit while adding a 419 replay to a shared axios instance.

Returning nothing from an error branch — the classic `if (status === 403) window.location.href = url`
with no `return Promise.reject(error)` — makes the promise **resolve with `undefined`**, so
`const { data } = await client.post(…)` throws `TypeError: Cannot read properties of undefined` and
the real status is lost. Always end an error interceptor with a rejection; navigate _and_ reject.

Guard the status read: `error.response?.status`, never `error.response.status` — a network failure,
timeout or abort carries no `response`, so the unguarded form turns it into the same `TypeError`.

Replaying the request is safe for the token: axios attaches `X-XSRF-TOKEN` in `resolveConfig` at
dispatch time, reading `document.cookie` and setting the header on a **copy** (`mergeConfig({}, config)`),
so re-issuing `client.request(error.config)` re-reads a freshly seeded cookie instead of resending the
stale header. A per-request flag on the config is the loop guard — and a nested request (the cookie
seed itself) needs that flag propagated, or it recurses.
