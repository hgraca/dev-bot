---
date: 2026-09-25
keywords: ["bun", "mock-module", "opencode", "tui-plugin", "testing"]
trigger-on: ["bun-test-mock-module", "opencode-tui-plugin-test"]
---

## Testing an opencode TUI plugin headlessly with `mock.module`

An opencode TUI plugin imports `@opentui/solid` and `solid-js`, which are not installed in the host project, so `bun test` cannot import the plugin directly. Calling `mock.module("@opentui/solid", …)` and `mock.module("solid-js", …)` before an `await import("./index")` makes it loadable — but the mocks must be **functional**, not no-ops, or the tests prove nothing: `setProp` has to record props and `insertNode` has to keep children, so a registered slot's element tree can be walked to reach a handler (for example a sidebar header's `onMouseDown`); and `createSignal` must be **stateful** (a real getter plus a setter that assigns) or a toggle's `collapsed()` never flips and the branch that must NOT fire is untestable. For a plugin that discovers something through `/proc`, a listener the test process owns is genuinely discoverable — `Bun.serve({ hostname: "::1", port: 0 })` appears in both `/proc/self/fd` and `/proc/self/net/tcp6` — which lets a test hang discovery by stubbing `globalThis.fetch`. Always assert the stub was actually reached: if the fixture's listener is not discovered the refresh just finishes, and the test passes vacuously while guarding nothing.
