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

import { describe, expect, mock, setDefaultTimeout, setSystemTime, test } from "bun:test"

// A wait resumes on progress, so a slow machine costs latency, not a red
// suite. Give the per-test budget room for a wait's own safety deadline (below)
// to be the thing that expires, rather than bun cutting the test off mid-wait.
setDefaultTimeout(30_000)

type El = { tag: string; props: Record<string, unknown>; children: El[]; text?: string }

/**
 * Wake-ups for `waitFor`.
 *
 * Every mocked state change and every side effect a test can wait on pings
 * these listeners, so a wait resumes the moment the plugin reports progress.
 * A short fixed poll interval with a short deadline would instead make a loaded
 * machine look like a broken plugin: nothing is wrong, the timer just did not
 * fire in time. Timers below are only a liveness net for a condition that can
 * turn true without a mocked signal.
 */
const progressListeners = new Set<() => void>()

function reportProgress() {
  for (const wake of progressListeners) wake()
}

mock.module("@opentui/solid", () => {
  // Text nodes carry their content in `text`, like the real renderable, so a
  // test can read a label the panel rendered from an accessor.
  const textNode = (value: unknown): El => ({
    tag: "#text",
    props: {},
    children: [],
    text: String(value),
  })
  return {
    createElement: (tag: string): El => ({ tag, props: {}, children: [] }),
    createTextNode: textNode,
    // Real `insert` handles a reactive accessor, and the panel renders both its
    // row list and its reactive labels that way. The mock must resolve the
    // accessor and attach what it yields — elements AND strings — or no test
    // could reach a rendered row or read a rendered label.
    insert: (parent: El, child: unknown) => {
      const value = typeof child === "function" ? (child as () => unknown)() : child
      for (const item of Array.isArray(value) ? value : [value]) {
        if (item && typeof item === "object") parent.children.push(item as El)
        else if (typeof item === "string") parent.children.push(textNode(item))
      }
    },
    insertNode: (parent: El, child: El) => {
      parent.children.push(child)
    },
    setProp: (el: El, key: string, value: unknown) => {
      el.props[key] = value
    },
  }
})

// Stateful on purpose: the expand/collapse contract is only testable if the
// panel's `collapsed` signal actually flips on a click.
mock.module("solid-js", () => ({
  createSignal: (init: unknown) => {
    let value = init
    return [
      () => value,
      (next: unknown) => {
        value = typeof next === "function" ? (next as (prev: unknown) => unknown)(value) : next
        reportProgress()
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
function stubApi(options: { rejectCreate?: boolean; throwingToast?: boolean } = {}) {
  let dispose: (() => void) | null = null
  let commands: (() => { onSelect: () => void }[]) | null = null
  let slots: { slots: { sidebar_content: () => El } } | null = null
  let confirm: { onConfirm?: () => void; title?: string; message?: string } | null = null
  let dialogTree: El | null = null
  const calls = {
    slots: 0,
    commands: 0,
    serverStarts: 0,
    dialogs: 0,
    confirms: 0,
    toasts: [] as string[],
  }
  const sidebar = () => slots!.slots.sidebar_content()
  return {
    calls,
    disposeNow: () => dispose?.(),
    /** The rendered sidebar tree, rebuilt from the plugin's current state. */
    sidebar,
    /** The props the plugin handed to the most recent confirm dialog. */
    confirmProps: () => confirm,
    /** The rendered tree of the most recent dialog, or null before one opened. */
    dialogElement: () => dialogTree,
    /** Ask for a start the first way: the slash command. */
    runExplicitRequest: () => {
      const list = commands ? commands() : []
      list[0]?.onSelect()
    },
    /** Ask for a start the second way: click the header (toggles collapse). */
    clickHeader: () => {
      // The header is a row holding the toggle text first and the clear action
      // second; the toggle is what the panel binds the collapse to.
      const toggle = sidebar().children[0]!.children[0]!
      ;(toggle.props.onMouseDown as () => void)()
    },
    api: {
      kv: { get: (_key: string, fallback: unknown) => fallback, set: () => {} },
      slots: {
        register: (def: { slots: { sidebar_content: () => El } }) => {
          calls.slots++
          slots = def
          reportProgress()
        },
      },
      command: {
        register: (fn: () => { onSelect: () => void }[]) => {
          calls.commands++
          commands = fn
          reportProgress()
        },
      },
      lifecycle: {
        onDispose: (fn: () => void) => {
          dispose = fn
        },
      },
      theme: { current: {} },
      ui: {
        toast: (input: { variant?: string }) => {
          calls.toasts.push(input.variant || "info")
          reportProgress()
          // Models a host toast that throws, so the plugin's best-effort
          // handling around it is exercised rather than assumed.
          if (options.throwingToast) throw new Error("toast exploded")
        },
        DialogConfirm: (props: unknown) => {
          calls.confirms++
          confirm = props as { onConfirm?: () => void }
          reportProgress()
          return { tag: "confirm", props: {}, children: [] }
        },
        // Counts every dialog the plugin pushes, so a test can tell a removal
        // confirm apart from the output dialog opening on the row behind a `✕`.
        // The rendered tree is kept so a test can read what the dialog says.
        dialog: {
          replace: (render: () => unknown) => {
            calls.dialogs++
            dialogTree = render() as El
            reportProgress()
          },
          clear: () => {},
          setSize: () => {},
        },
      },
      state: { session: { messages: () => [] } },
      renderer: {},
      client: {
        session: {
          create: () => {
            calls.serverStarts++
            reportProgress()
            return options.rejectCreate
              ? Promise.reject(new Error("create failed"))
              : new Promise(() => {})
          },
        },
      },
    },
  }
}

/**
 * How long a wait keeps watching for progress before it gives up.
 *
 * This is a safety net for a condition that never becomes true — a broken
 * assertion should still fail — NOT the mechanism: a wait wakes on the next
 * progress signal, so CPU contention only delays how soon the check runs.
 */
const WAIT_SAFETY_MS = 10_000

/**
 * How often a wait re-checks a condition that has no mocked signal behind it.
 *
 * Progress wakes it sooner; this only stops a condition that becomes true by
 * other means (a fixture server answering, say) from waiting out the deadline.
 */
const WAIT_LIVENESS_MS = 250

/** Wait until `cond` holds. Keeps the tests free of fixed sleeps. */
async function waitFor(cond: () => boolean, ms = WAIT_SAFETY_MS): Promise<boolean> {
  if (cond()) return true
  // Monotonic: a test may freeze `Date.now` to pin a rendered duration.
  const deadline = performance.now() + ms
  let wake: (() => void) | null = null
  const listener = () => wake?.()
  progressListeners.add(listener)
  try {
    while (!cond()) {
      if (performance.now() >= deadline) return false
      await new Promise<void>((resolve) => {
        // Cleared by the progress listener, so a busy run does not leave a
        // timer per wait behind it.
        const timer = setTimeout(resolve, WAIT_LIVENESS_MS)
        wake = () => {
          clearTimeout(timer)
          resolve()
        }
      })
      wake = null
    }
    return true
  } finally {
    progressListeners.delete(listener)
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
      reportProgress()
      return new Promise(() => {})
    }) as typeof fetch
    const { api, calls, disposeNow } = stubApi()
    try {
      // The bound detects a factory that BLOCKS on discovery, not one that is
      // slow to load: promptness is not asserted here.
      const outcome = await Promise.race([
        plugin.tui(api as never).then(() => "resolved"),
        new Promise((resolve) => setTimeout(() => resolve("blocked"), WAIT_SAFETY_MS)),
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
    const stub = stubApi()
    const { calls, disposeNow } = stub
    try {
      await plugin.tui(stub.api as never)
      // The load-time refresh is detached, so wait for its observable outcome
      // (no server found -> the idle status) instead of sleeping on a guess.
      expect(await waitFor(() => headerText(stub).includes("not running"))).toBe(true)
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
      expect(await waitFor(() => calls.serverStarts > 0)).toBe(true)
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
    const stub = stubApi({ rejectCreate: true })
    const { calls, disposeNow, clickHeader } = stub
    try {
      await plugin.tui(stub.api as never)
      clickHeader() // expand -> asks
      expect(await waitFor(() => calls.serverStarts > 0)).toBe(true)
      // Let the attempt finish before sampling: the failing create's status is
      // the progress signal that says the bootstrap has settled.
      expect(await waitFor(() => headerText(stub).includes("starting server"))).toBe(true)
      const afterExpand = calls.serverStarts
      clickHeader() // collapse -> must NOT ask
      await new Promise((resolve) => setTimeout(resolve, 100))
      expect(calls.serverStarts).toBe(afterExpand)
    } finally {
      disposeNow()
    }
  })

  test("bounds every probe with an abort signal", async () => {
    // The regression this guards: reverting fetchWithTimeout to a bare fetch()
    // leaves the probe unbounded, so a peer that accepts but never answers holds
    // the refresh — and the overlap guard behind it — open forever.
    const listener = Bun.serve({ hostname: "::1", port: 0, fetch: () => new Response("nope") })
    const realFetch = globalThis.fetch
    const signals: unknown[] = []
    globalThis.fetch = ((_url: string, init?: { signal?: unknown }) => {
      signals.push(init?.signal)
      return new Promise(() => {})
    }) as typeof fetch
    const { api, disposeNow } = stubApi()
    try {
      await plugin.tui(api as never)
      expect(await waitFor(() => signals.length > 0)).toBe(true) // a probe went out
      expect(signals.every((s) => s instanceof AbortSignal)).toBe(true) // and bounded
    } finally {
      globalThis.fetch = realFetch
      listener.stop(true)
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
      expect(await waitFor(() => calls.serverStarts > beforeRetry)).toBe(true)
    } finally {
      disposeNow()
    }
  })
})

/**
 * A stand-in for opencode-pty's HTTP server: answers the health probe the
 * discovery path uses, serves the session list, and records every cleanup
 * request. Bound to `::1` so the plugin's `/proc` scan finds it exactly the way
 * it finds the real server.
 */
function ptyFixture(sessions: unknown[]) {
  const deletes: string[] = []
  const server = Bun.serve({
    hostname: "::1",
    port: 0,
    fetch: (req) => {
      const url = new URL(req.url)
      if (url.pathname === "/health") {
        return Response.json({
          status: "healthy",
          sessions: { total: sessions.length, active: 0 },
        })
      }
      if (url.pathname === "/api/sessions" && req.method === "GET") {
        return Response.json(sessions)
      }
      if (req.method === "DELETE" && url.pathname.endsWith("/cleanup")) {
        deletes.push(url.pathname)
        reportProgress()
        // Serve the list WITHOUT the removed session afterwards, so a test can
        // observe that the panel's own refresh ran rather than inferring it.
        const id = url.pathname.split("/")[3]
        const at = sessions.findIndex((s) => (s as { id?: unknown }).id === id)
        if (at >= 0) sessions.splice(at, 1)
        return Response.json({ success: true })
      }
      return new Response("not found", { status: 404 })
    },
  })
  return { server, deletes }
}

/** The panel's rendered rows — the sidebar's second child is the live column. */
function rowsOf(stub: ReturnType<typeof stubApi>) {
  return stub.sidebar().children[1]?.children ?? []
}

/**
 * Wait until `count` real session rows are rendered.
 *
 * Filters on `box`: an empty list renders a `text` placeholder, and waiting on
 * a bare non-empty count would match that and race every assertion behind it.
 */
function waitForRows(stub: ReturnType<typeof stubApi>, count: number) {
  return waitFor(() => rowsOf(stub).filter((r) => r.tag === "box").length === count)
}

/**
 * Start the plugin with periodic polling switched off.
 *
 * A test that proves "the refresh a removal triggers is what updates the list"
 * cannot also let the background poll run: a broken forced refresh would be
 * rescued by the next tick, and a wait generous enough for a loaded machine
 * would happily accept that. Patching only the factory call is enough — the
 * interval handle is never created, so nothing needs restoring afterwards.
 */
async function startWithoutPolling(api: unknown) {
  const realSetInterval = globalThis.setInterval
  globalThis.setInterval = (() => 0) as unknown as typeof setInterval
  try {
    await plugin.tui(api as never)
  } finally {
    globalThis.setInterval = realSetInterval
  }
}

/** A row's `✕`: the bullet, the label, then the remove glyph. */
function removeControl(row: El) {
  return row.children[2]!
}

/** The header's rendered text: chevron, panel name, status. */
function headerText(stub: ReturnType<typeof stubApi>) {
  return stub.sidebar().children[0]!.children[0]!.children[0]?.text ?? ""
}

/** The header's clear-finished label as rendered ("" when there is none). */
function clearLabelOf(stub: ReturnType<typeof stubApi>) {
  const clear = stub.sidebar().children[0]!.children[1]!
  return clear.children[0]?.text ?? ""
}

/** Fire a control's mouse handler with a fake event that records the stop. */
function clickControl(handler: unknown, stopped: { value: boolean }) {
  ;(handler as (evt: unknown) => void)({
    stopPropagation: () => {
      stopped.value = true
    },
  })
}

/** Every text node's content in a rendered element tree. */
function textNodesOf(element: El | null): string[] {
  if (!element) return []
  const found: string[] = []
  const walk = (node: El) => {
    if (node.text !== undefined) found.push(node.text)
    for (const child of node.children) walk(child)
  }
  walk(element)
  return found
}

describe("pty-monitor session removal", () => {
  test("✕ on a finished session removes it without opening the dialog", async () => {
    const { server, deletes } = ptyFixture([
      { id: "pty_aaaa", title: "sleep 300", status: "exited", exitCode: 0, lineCount: 3 },
    ])
    const stub = stubApi()
    try {
      // No background poll: the row going away below must be the removal's own
      // forced refresh, not the next tick.
      await startWithoutPolling(stub.api)
      stub.clickHeader() // expand; the panel starts collapsed
      expect(await waitForRows(stub, 1)).toBe(true)
      // Discovery reached the fixture, so no throwaway bootstrap session ran.
      expect(stub.calls.serverStarts).toBe(0)

      const stopped = { value: false }
      clickControl(removeControl(rowsOf(stub)[0]!).props.onMouseUp, stopped)
      expect(stopped.value).toBe(true)
      expect(await waitFor(() => deletes.length > 0)).toBe(true)
      expect(deletes[0]).toBe("/api/sessions/pty_aaaa/cleanup")

      // The removal's own refresh must land promptly: the fixture now serves the
      // list without that session, so the row going away inside this window is
      // the observable proof the refresh ran (the poll is 2.5s off).
      expect(await waitFor(() => rowsOf(stub).filter((r) => r.tag === "box").length === 0)).toBe(
        true,
      )

      // The finished branch must push no dialog at all — neither the removal
      // confirm nor the output dialog. (That the event was actually suppressed is
      // proven above by the stopPropagation call-check; this mock does not
      // simulate bubbling, so this assertion cannot prove it.)
      await new Promise((resolve) => setTimeout(resolve, 20))
      expect(stub.calls.dialogs).toBe(0)
    } finally {
      server.stop(true)
      stub.disposeNow()
    }
  })

  test("✕ on a running session asks first, then removes", async () => {
    const { server, deletes } = ptyFixture([
      { id: "pty_bbbb", title: "make test", status: "running", lineCount: 12 },
    ])
    const stub = stubApi()
    try {
      await plugin.tui(stub.api as never)
      stub.clickHeader()
      expect(await waitForRows(stub, 1)).toBe(true)

      clickControl(removeControl(rowsOf(stub)[0]!).props.onMouseUp, { value: false })
      // A live process: the dialog is up and nothing has been killed yet.
      expect(stub.calls.confirms).toBe(1)
      expect(deletes).toEqual([])

      stub.confirmProps()!.onConfirm!()
      expect(await waitFor(() => deletes.length > 0)).toBe(true)
      expect(deletes[0]).toBe("/api/sessions/pty_bbbb/cleanup")
    } finally {
      server.stop(true)
      stub.disposeNow()
    }
  })

  test("clear finished removes every stopped session and no other", async () => {
    const { server, deletes } = ptyFixture([
      { id: "pty_run", title: "make test", status: "running", lineCount: 1 },
      { id: "pty_end", title: "sleep 60", status: "exited", exitCode: 0, lineCount: 2 },
      { id: "pty_kil", title: "sleep 5", status: "killed", lineCount: 4 },
      // Transient, not finished: a clear that raced the process teardown would
      // be a bug, so it must be left alone.
      { id: "pty_ing", title: "stopping", status: "killing", lineCount: 0 },
    ])
    const stub = stubApi()
    try {
      await plugin.tui(stub.api as never)
      stub.clickHeader()
      expect(await waitForRows(stub, 4)).toBe(true)

      const clear = stub.sidebar().children[0]!.children[1]!
      // The header offers the action only while something can be cleared.
      expect(clearLabelOf(stub)).toBe("(clear finished)")
      const stopped = { value: false }
      clickControl(clear.props.onMouseDown, stopped)
      expect(stopped.value).toBe(true) // the click must not also collapse the panel
      expect(await waitFor(() => deletes.length === 2)).toBe(true)
      expect(deletes.sort()).toEqual([
        "/api/sessions/pty_end/cleanup",
        "/api/sessions/pty_kil/cleanup",
      ])
    } finally {
      server.stop(true)
      stub.disposeNow()
    }
  })

  test("a throwing success toast is not reported as a failed removal", async () => {
    const { server, deletes } = ptyFixture([
      { id: "pty_zzzz", title: "sleep 5", status: "exited", exitCode: 0, lineCount: 1 },
    ])
    const stub = stubApi({ throwingToast: true })
    try {
      await plugin.tui(stub.api as never)
      stub.clickHeader()
      expect(await waitForRows(stub, 1)).toBe(true)

      clickControl(removeControl(rowsOf(stub)[0]!).props.onMouseUp, { value: false })
      expect(await waitFor(() => deletes.length > 0)).toBe(true)
      // The removal's own refresh is the point where both toast branches have
      // run, so sample the toasts after it rather than racing the response.
      expect(await waitForRows(stub, 0)).toBe(true)
      // The success toast threw. The removal still succeeded, so it must NOT be
      // followed by a failure toast — reporting it as failed is the regression
      // this pins.
      expect(stub.calls.toasts).toEqual(["info"])
    } finally {
      server.stop(true)
      stub.disposeNow()
    }
  })

  test("clear finished touches nothing while every session is still live", async () => {
    const { server, deletes } = ptyFixture([
      { id: "pty_run", title: "make test", status: "running", lineCount: 1 },
    ])
    const stub = stubApi()
    try {
      await plugin.tui(stub.api as never)
      stub.clickHeader()
      expect(await waitForRows(stub, 1)).toBe(true)

      const clear = stub.sidebar().children[0]!.children[1]!
      // Nothing is finished, so the header must offer no clear action at all.
      expect(clearLabelOf(stub)).toBe("")
      clickControl(clear.props.onMouseDown, { value: false })
      await new Promise((resolve) => setTimeout(resolve, 50))
      expect(deletes).toEqual([])
    } finally {
      server.stop(true)
      stub.disposeNow()
    }
  })
})

describe("pty-monitor output dialog", () => {
  test("shows how long the process has run, fixed once it exits", async () => {
    // Freeze the clock for the whole test — Date.now and `new Date` — so the
    // expected label does not depend on how long setup took: the finished
    // session ran exactly one minute, and the running one is exactly 90s old at
    // every render. Restored in the finally, including when setup throws.
    const base = Date.now()
    setSystemTime(base)
    const stub = stubApi()
    let server: ReturnType<typeof ptyFixture>["server"] | null = null
    try {
      server = ptyFixture([
        {
          id: "pty_done",
          title: "build",
          status: "exited",
          exitCode: 0,
          lineCount: 1,
          createdAt: new Date(base - 65_000).toISOString(),
          exitAt: new Date(base - 5_000).toISOString(),
        },
        {
          id: "pty_live",
          title: "dev server",
          status: "running",
          lineCount: 3,
          createdAt: new Date(base - 90_000).toISOString(),
        },
      ]).server
      await plugin.tui(stub.api as never)
      stub.clickHeader() // expand
      expect(await waitForRows(stub, 2)).toBe(true)

      // A finished session: 65s - 5s before the fixture base = one minute, shown
      // as a fixed figure in the header's bottom-right corner.
      clickControl(rowsOf(stub)[0]!.props.onMouseUp, { value: false })
      expect(await waitFor(() => stub.dialogElement() !== null)).toBe(true)
      const finished = textNodesOf(stub.dialogElement())
      expect(finished).toContain("esc to close")
      expect(finished).toContain("1m 00s")

      // A running one has no end yet, so it is measured from its start to now.
      clickControl(rowsOf(stub)[1]!.props.onMouseUp, { value: false })
      expect(await waitFor(() => textNodesOf(stub.dialogElement()).includes("1m 30s"))).toBe(true)
    } finally {
      setSystemTime()
      server?.stop(true)
      stub.disposeNow()
    }
  })
})
