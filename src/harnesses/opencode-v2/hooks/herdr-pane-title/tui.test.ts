// src/harnesses/opencode-v2/hooks/herdr-pane-title/tui.test.ts
// Tests for the v2 TUI part. The title rules themselves are covered once, beside
// the shared lib.ts; this file pins the v2 contract (async event stream, returned
// disposer) and the three moments a label can go stale.

import { afterAll, beforeAll, describe, expect, test } from "bun:test"
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import plugin, { setup } from "./tui"
import type { SessionInfo } from "./lib"

const route = (sessionID?: string) => ({
  current: sessionID === undefined ? { name: "home" } : { name: "session", params: { sessionID } },
})

/** A stand-in for v2's async event stream: push a v2-shaped event (payload in `data`). */
function eventStream() {
  const queue: unknown[] = []
  let wake: (() => void) | undefined
  return {
    push(event: unknown) {
      queue.push(event)
      wake?.()
      wake = undefined
    },
    subscribe({ signal }: { signal: AbortSignal }) {
      return {
        [Symbol.asyncIterator]() {
          return {
            async next() {
              while (queue.length === 0) {
                if (signal.aborted) throw Object.assign(new Error("aborted"), { name: "AbortError" })
                await new Promise<void>((resolve) => {
                  wake = resolve
                  signal.addEventListener("abort", () => resolve(), { once: true })
                })
              }
              return { value: queue.shift(), done: false }
            },
          }
        },
      } as unknown as AsyncIterable<unknown>
    },
  }
}

describe("v2 TUI part", () => {
  const KEYS = ["HERDR_ENV", "HERDR_PANE_ID", "HERDR_BIN_PATH", "PATH"] as const
  let saved: Record<string, string | undefined> = {}
  let dir: string
  let calls: string
  let stub: string

  const herdrCalls = () =>
    readFileSync(calls, "utf8")
      .split("\n")
      .filter(Boolean)
      .map((line) => line.split("|").slice(0, 4))

  const ctxFor = (records: SessionInfo[], shown = route("root")) => {
    const map = new Map(records.map((s) => [s.id, s]))
    const stream = eventStream()
    return {
      state: { session: { get: (id: string) => map.get(id) } },
      route: shown,
      event: { subscribe: stream.subscribe },
      push: stream.push,
    }
  }

  const restore = () => {
    for (const key of KEYS) {
      if (saved[key] === undefined) delete process.env[key]
      else process.env[key] = saved[key]
    }
  }

  const insideHerdr = () => {
    process.env.HERDR_ENV = "1"
    process.env.HERDR_PANE_ID = "w1:p1"
    process.env.HERDR_BIN_PATH = stub
    writeFileSync(calls, "")
  }

  beforeAll(() => {
    saved = Object.fromEntries(KEYS.map((key) => [key, process.env[key]]))
    dir = mkdtempSync(join(tmpdir(), "herdr-pane-title-v2-"))
    calls = join(dir, "calls")
    stub = join(dir, "herdr")
    writeFileSync(
      stub,
      `#!/bin/sh\nfor a in "$@"; do printf '%s|' "$a" >> '${calls}'; done\nprintf '\\n' >> '${calls}'\n`,
      { mode: 0o755 },
    )
    chmodSync(stub, 0o755)
    writeFileSync(calls, "")
  })

  afterAll(() => {
    restore()
    rmSync(dir, { recursive: true, force: true })
  })

  test("exports the shape v2 validates", () => {
    expect(plugin.id).toBe("herdr-pane-title")
    expect(typeof plugin.setup).toBe("function")
  })

  test("does nothing outside a herdr pane", () => {
    try {
      delete process.env.HERDR_ENV
      writeFileSync(calls, "")
      expect(setup(ctxFor([{ id: "root", title: "Root title" }]) as never)).toBeUndefined()
      expect(herdrCalls()).toEqual([])
    } finally {
      restore()
    }
  })

  test("a ctx without the session cache is a no-op, not a failure", () => {
    try {
      insideHerdr()
      expect(() => setup({ route: route("root") } as never)).not.toThrow()
      expect(herdrCalls()).toEqual([])
    } finally {
      restore()
    }
  })

  test("a title assigned after creation is applied from the event", async () => {
    let dispose: (() => void) | undefined
    try {
      insideHerdr()
      // The cache has no title yet: exactly the window after session.created.
      const ctx = ctxFor([{ id: "root" }])
      dispose = setup(ctx as never)
      await new Promise((r) => setTimeout(r, 150))
      expect(herdrCalls()).toEqual([])

      ctx.push({
        type: "session.updated",
        data: { sessionID: "root", info: { id: "root", title: "Generated later" } },
      })
      await new Promise((r) => setTimeout(r, 200))
      expect(herdrCalls()).toEqual([["pane", "rename", "w1:p1", "Generated later"]])
    } finally {
      dispose?.()
      restore()
    }
  })

  test("a session switch follows the new root, and the disposer clears the label", async () => {
    try {
      insideHerdr()
      const shown = route("root")
      const ctx = ctxFor(
        [
          { id: "root", title: "Root title" },
          { id: "other", title: "Other title" },
        ],
        shown,
      )
      const dispose = setup(ctx as never)
      expect(typeof dispose).toBe("function")
      await new Promise((r) => setTimeout(r, 150))

      // No event accompanies a switch, so this is the poll's job.
      shown.current = { name: "session", params: { sessionID: "other" } }
      await new Promise((r) => setTimeout(r, 700))
      expect(herdrCalls().at(-1)).toEqual(["pane", "rename", "w1:p1", "Other title"])

      dispose?.()
      await new Promise((r) => setTimeout(r, 200))
      expect(herdrCalls().at(-1)).toEqual(["pane", "rename", "w1:p1", "--clear"])
    } finally {
      restore()
    }
  })
})
