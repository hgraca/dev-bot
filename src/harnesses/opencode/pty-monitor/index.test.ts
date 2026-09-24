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

mock.module("solid-js", () => ({
  createSignal: (init: unknown) => [() => init, () => {}],
}))

const { default: plugin } = await import("./index")

/**
 * A stub api for the plugin.
 *
 * `session.create` is the bootstrap's first step — starting the server — so it
 * is what `calls.serverStarts` counts. It never settles, which also makes the
 * factory timing test meaningful: a factory that awaited a refresh which
 * bootstrapped would never resolve.
 */
function stubApi() {
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
    /** Ask for a start the second way: expand the sidebar panel. */
    expandPanel: () => {
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
            return new Promise(() => {})
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

/**
 * A refresh already in flight makes the next one a no-op, so an asker is
 * retried until one gets through rather than guessing how long the first takes.
 */
async function askUntilStarted(ask: () => void, calls: { serverStarts: number }) {
  return waitFor(() => {
    ask()
    return calls.serverStarts > 0
  })
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
    const { api, calls, disposeNow, runExplicitRequest } = stubApi()
    try {
      await plugin.tui(api as never)
      expect(calls.serverStarts).toBe(0)
      expect(await askUntilStarted(runExplicitRequest, calls)).toBe(true)
    } finally {
      disposeNow()
    }
  })

  test("starts the PTY server when the panel is expanded", async () => {
    const { api, calls, disposeNow, expandPanel } = stubApi()
    try {
      await plugin.tui(api as never)
      expect(calls.serverStarts).toBe(0)
      expect(await askUntilStarted(expandPanel, calls)).toBe(true)
    } finally {
      disposeNow()
    }
  })
})
