// =============================================================================
// src/harnesses/opencode/pty-monitor/index.test.ts
// Regression tests for the plugin factory's STARTUP contract.
//
// Three things must hold, all learned the hard way from the startup trace:
//
//  1. The factory must not await its first refresh. opencode's TUI plugin loader
//     awaits every plugin factory before the TUI becomes usable, showing its
//     "Loading plugins…" overlay the whole time.
//  2. Loading must not start the PTY server. opencode-pty starts it only from a
//     command handler, and the trigger for that is a throwaway session — server
//     initialisation plus a session create/delete does not belong on the
//     startup path.
//  3. A start must still be reachable when the user asks: the slash command and
//     expanding the sidebar panel are the two ways to ask.
//
// The TUI half cannot be driven headlessly, so the two display-only imports are
// mocked and the api is stubbed; the assertions are about timing and side
// effects, not rendering.
// =============================================================================

import { describe, expect, mock, test } from "bun:test"

type El = { tag: string; props: Record<string, unknown>; children: El[] }

mock.module("@opentui/solid", () => ({
  createElement: (tag: string): El => ({ tag, props: {}, children: [] }),
  createTextNode: (text: unknown) => ({ text: String(text) }),
  insert: () => {},
  insertNode: (parent: El, child: El) => {
    parent.children.push(child)
  },
  setProp: (el: El, key: string, value: unknown) => {
    el.props[key] = value
  },
}))

// Stateful on purpose: the expand/collapse contract is only testable if the
// panel's `collapsed` signal actually flips on a click.
mock.module("solid-js", () => ({
  createSignal: (init: unknown) => {
    let value = init
    return [
      () => value,
      (next: unknown) => {
        value = typeof next === "function" ? (next as (prev: unknown) => unknown)(value) : next
      },
    ]
  },
}))

const { default: plugin } = await import("./index")

/**
 * A stub api for the plugin.
 *
 * `session.create` is the bootstrap's first step — starting the server — so it
 * is what `calls.serverStarts` counts. By default it never settles, which also
 * makes the factory timing test meaningful: a factory that awaited a refresh
 * which bootstrapped would never resolve. `rejectCreate` models a bootstrap that
 * fails outright, which is how the backoff path is reached.
 */
function stubApi(options: { rejectCreate?: boolean } = {}) {
  let dispose: (() => void) | null = null
  let commands: (() => { onSelect: () => void }[]) | null = null
  let slots: { slots: { sidebar_content: () => El } } | null = null
  const calls = { slots: 0, commands: 0, serverStarts: 0 }
  return {
    calls,
    disposeNow: () => dispose?.(),
    /** Ask for a start the first way: the slash command. */
    runExplicitRequest: () => {
      const list = commands ? commands() : []
      list[0]?.onSelect()
    },
    /** Ask for a start the second way: click the header (toggles collapse). */
    clickHeader: () => {
      const header = slots!.slots.sidebar_content().children[0]!
      ;(header.props.onMouseDown as () => void)()
    },
    api: {
      kv: { get: (_key: string, fallback: unknown) => fallback, set: () => {} },
      slots: {
        register: (def: { slots: { sidebar_content: () => El } }) => {
          calls.slots++
          slots = def
        },
      },
      command: {
        register: (fn: () => { onSelect: () => void }[]) => {
          calls.commands++
          commands = fn
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
      client: {
        session: {
          create: () => {
            calls.serverStarts++
            return options.rejectCreate
              ? Promise.reject(new Error("create failed"))
              : new Promise(() => {})
          },
        },
      },
    },
  }
}

/** Wait until `cond` holds, or give up. Keeps the tests free of fixed sleeps. */
async function waitFor(cond: () => boolean, ms = 750): Promise<boolean> {
  const deadline = Date.now() + ms
  while (!cond() && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 10))
  }
  return cond()
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

  test("does not start the PTY server on load", async () => {
    const { api, calls, disposeNow } = stubApi()
    try {
      await plugin.tui(api as never)
      // Let the detached load-time refresh run its course.
      await new Promise((resolve) => setTimeout(resolve, 100))
      expect(calls.serverStarts).toBe(0)
    } finally {
      disposeNow()
    }
  })

  test("starts the PTY server when the slash command asks", async () => {
    // Hold the load refresh open so the ask lands while one is provably in
    // flight. The overlap guard must DEFER an explicit ask, never drop it — the
    // user clicks once, they do not retry in a loop.
    const listener = Bun.serve({ hostname: "::1", port: 0, fetch: () => new Response("nope") })
    const realFetch = globalThis.fetch
    let released = false
    let release: (() => void) | null = null
    globalThis.fetch = (() => {
      if (released) return Promise.reject(new Error("no"))
      return new Promise((_, reject) => {
        release = () => {
          released = true
          reject(new Error("no"))
        }
      })
    }) as typeof fetch
    const { api, calls, disposeNow, runExplicitRequest } = stubApi()
    try {
      await plugin.tui(api as never)
      expect(release).not.toBeNull() // the load refresh really is mid-discovery
      runExplicitRequest() // arrives while that refresh is still in flight
      release!()
      expect(await waitFor(() => calls.serverStarts > 0, 1500)).toBe(true)
    } finally {
      globalThis.fetch = realFetch
      listener.stop(true)
      disposeNow()
    }
  })

  test("starts the PTY server when the panel is expanded", async () => {
    const { api, calls, disposeNow, clickHeader } = stubApi()
    try {
      await plugin.tui(api as never)
      expect(calls.serverStarts).toBe(0)
      clickHeader() // the panel starts collapsed, so this expands it
      expect(await waitFor(() => calls.serverStarts > 0)).toBe(true)
    } finally {
      disposeNow()
    }
  })

  test("does not start the PTY server when the panel is collapsed", async () => {
    // A failing create keeps every attempt short-lived, so a spurious ask on
    // collapse would show up as a real extra attempt rather than being deferred.
    const { api, calls, disposeNow, clickHeader } = stubApi({ rejectCreate: true })
    try {
      await plugin.tui(api as never)
      clickHeader() // expand -> asks
      expect(await waitFor(() => calls.serverStarts > 0)).toBe(true)
      await new Promise((resolve) => setTimeout(resolve, 50)) // let it settle
      const afterExpand = calls.serverStarts
      clickHeader() // collapse -> must NOT ask
      await new Promise((resolve) => setTimeout(resolve, 100))
      expect(calls.serverStarts).toBe(afterExpand)
    } finally {
      disposeNow()
    }
  })

  test("expanding retries once the bootstrap backoff has engaged", async () => {
    const { api, calls, disposeNow, clickHeader } = stubApi({ rejectCreate: true })
    try {
      await plugin.tui(api as never)
      // Three expand-triggered failures engage the backoff; the collapse clicks
      // in between are what let the next expand happen at all.
      for (let i = 0; i < 3; i++) {
        const before = calls.serverStarts
        clickHeader() // expand
        expect(await waitFor(() => calls.serverStarts > before)).toBe(true)
        clickHeader() // collapse
      }
      // Backing off must not make the panel a dead end: expanding again retries.
      const beforeRetry = calls.serverStarts
      clickHeader() // expand
      expect(await waitFor(() => calls.serverStarts > beforeRetry, 1500)).toBe(true)
    } finally {
      disposeNow()
    }
  })
})
