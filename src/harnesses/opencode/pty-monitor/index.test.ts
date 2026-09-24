// =============================================================================
// src/harnesses/opencode/pty-monitor/index.test.ts
// Regression test for the plugin factory's STARTUP contract.
//
// opencode's TUI plugin loader awaits every plugin factory before the TUI
// becomes usable, showing its "Loading plugins…" overlay for the whole time
// (see TuiPluginRuntime.start -> for(…) await activate(plugin)). The factory
// therefore MUST NOT await the first refresh: origin discovery can block for
// seconds, because with no PTY server listening it bootstraps one through a
// throwaway session. Awaiting it stalled every opencode start.
//
// The TUI half cannot be driven headlessly, so the two display-only imports are
// mocked and the api is stubbed; the assertion is purely about timing.
// =============================================================================

import { describe, expect, mock, test } from "bun:test"

mock.module("@opentui/solid", () => ({
  createElement: () => ({}),
  createTextNode: () => ({}),
  insert: () => {},
  insertNode: () => {},
  setProp: () => {},
}))

mock.module("solid-js", () => ({
  createSignal: (init: unknown) => [() => init, () => {}],
}))

const { default: plugin } = await import("./index")

/**
 * An api whose origin resolution can never settle: `session.create` — the first
 * thing the bootstrap does — returns a promise that never resolves. If the
 * factory awaits its first refresh, the factory never resolves either.
 */
function stubApi() {
  let dispose: (() => void) | null = null
  const calls = { slots: 0, commands: 0 }
  return {
    calls,
    disposeNow: () => dispose?.(),
    api: {
      kv: { get: (_key: string, fallback: unknown) => fallback, set: () => {} },
      slots: {
        register: () => {
          calls.slots++
        },
      },
      command: {
        register: () => {
          calls.commands++
        },
      },
      lifecycle: {
        onDispose: (fn: () => void) => {
          dispose = fn
        },
      },
      theme: { current: {} },
      ui: { toast: () => {} },
      state: { session: { messages: () => [] } },
      renderer: {},
      client: { session: { create: () => new Promise(() => {}) } },
    },
  }
}

describe("pty-monitor tui factory", () => {
  /**
   * Hang discovery deterministically: a listener this process owns is found by
   * the plugin's `/proc` scan, and the fetch it makes next never settles. A
   * factory that awaited its first refresh could therefore never resolve.
   *
   * The `probed` assertion is the point of the test. If the fixture's listener
   * is ever not discovered (no `/proc`, IPv6 unavailable), the refresh would
   * finish after the scan and the test would pass vacuously — so it fails loudly
   * instead, which is what makes this a real guard rather than a tautology.
   */
  test("resolves without waiting for a discovery that never answers", async () => {
    const listener = Bun.serve({ hostname: "::1", port: 0, fetch: () => new Response("nope") })
    const realFetch = globalThis.fetch
    let probed = false
    globalThis.fetch = (() => {
      probed = true
      return new Promise(() => {})
    }) as typeof fetch
    const { api, calls, disposeNow } = stubApi()
    try {
      const outcome = await Promise.race([
        plugin.tui(api as never).then(() => "resolved"),
        new Promise((resolve) => setTimeout(() => resolve("blocked"), 750)),
      ])
      expect(probed).toBe(true) // the fixture listener really was discovered
      expect(outcome).toBe("resolved") // and the factory resolved anyway
      expect(calls.slots).toBe(1)
      expect(calls.commands).toBe(1)
    } finally {
      globalThis.fetch = realFetch
      listener.stop(true)
      disposeNow()
    }
  })
})
