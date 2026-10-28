---
date: 2026-10-28
keywords: ["bun", "setTimeout", "timeout", "timer"]
---

## A `setTimeout` delay above 2^31-1 ms is clamped to 1 ms, not to "forever"

Node and Bun (verified on bun 1.3.13) reject a timer delay larger than `2_147_483_647` ms by
emitting a `TimeoutOverflowWarning` and setting the delay to **1 ms**. The intent behind a huge
value — "effectively no timeout" — inverts: the callback fires almost immediately.

This bites any configurable timeout that trusts its input. A tool declaring
`timeoutMs: 90000000000` (a plausible typo for 15 minutes) is killed within milliseconds, and the
only signal is a timeout error after the work never ran. The same overflow applies to a derived
delay: `timeoutMs + 5_000` at the ceiling wraps the same way, so clamp derived values too.

Validate the value, do not just parse it: require a real JSON number
(`typeof value === "number"` — `Number(true)` is `1` and `Number("5000")` is `5000`), then
`Number.isSafeInteger(ms) && ms > 0 && ms <= 2_147_483_647`, and fall back to the default for
anything else. Accepting a coerced or out-of-range value converts "give it more time" into "kill it
now".
