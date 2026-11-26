// Tests for the v2 TUI part: the 2.x context shape
// and the three moments a label goes stale.

import { afterAll, beforeAll, describe, expect, test } from "bun:test"
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import plugin, { setup } from "./tui"
import type { SessionInfo } from "./lib"

type SessionEvent = { type?: string; data?: Record<string, unknown> }
type Route = { type: string; sessionID?: string }

const route = (sessionID?: string): Route =>
  sessionID === undefined ? { type: "home" } : { type: "session", sessionID }

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

/** A 2.x ctx stand-in; a delete also drops
 *  the cache record, as the host's store does. */
function host(records: SessionInfo[], shown: Route = route("root")) {
  const sessions = new Map(records.map((s) => [s.id, s]))
  const handlers = new Map<string, Array<(event: SessionEvent) => void>>()
  return {
    ctx: {
      data: {
        session: { get: (id: string) => sessions.get(id) },
        on: (type: string, handler: (event: SessionEvent) => void) => {
          const list = handlers.get(type) ?? []
          list.push(handler)
          handlers.set(type, list)
          return () => handlers.set(type, (handlers.get(type) ?? []).filter((h) => h !== handler))
        },
      },
      ui: { router: { current: () => shown } },
    },
    emit(type: string, data: Record<string, unknown>) {
      if (type === "session.deleted" && typeof data.sessionID === "string") sessions.delete(data.sessionID)
      for (const handler of handlers.get(type) ?? []) handler({ type, data })
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
      const h = host([{ id: "root", title: "Root title" }])
      expect(setup(h.ctx as never)).toBeUndefined()
      expect(herdrCalls()).toEqual([])
    } finally {
      restore()
    }
  })

  test("a ctx without the session cache or the router is a no-op, not a failure", () => {
    try {
      insideHerdr()
      expect(() => setup({ ui: { router: { current: () => route() } } } as never)).not.toThrow()
      expect(() => setup({ data: { session: { get: () => undefined } } } as never)).not.toThrow()
      expect(herdrCalls()).toEqual([])
    } finally {
      restore()
    }
  })

  test("a title assigned after creation is applied from the event", async () => {
    let dispose: (() => void) | undefined
    try {
      insideHerdr()
      // No cache title yet, as after session.created.
      const h = host([{ id: "root" }])
      dispose = setup(h.ctx as never, 10)
      await wait(100)
      expect(herdrCalls()).toEqual([])

      h.emit("session.renamed", { sessionID: "root", title: "Generated later" })
      await wait(150)
      expect(herdrCalls()).toEqual([["pane", "rename", "w1:p1", "Generated later"]])
    } finally {
      dispose?.()
      await wait(100)
      restore()
    }
  })

  test("a title carried by session.created labels a session the cache lacks", async () => {
    let dispose: (() => void) | undefined
    try {
      insideHerdr()
      const h = host([], route("root"))
      dispose = setup(h.ctx as never, 10)
      await wait(100)
      expect(herdrCalls()).toEqual([])

      h.emit("session.created", { sessionID: "root", title: "Fresh title" })
      await wait(150)
      expect(herdrCalls()).toEqual([["pane", "rename", "w1:p1", "Fresh title"]])
    } finally {
      dispose?.()
      await wait(100)
      restore()
    }
  })

  test("a child session's rename keeps the root session's label", async () => {
    let dispose: (() => void) | undefined
    try {
      insideHerdr()
      const h = host(
        [
          { id: "root", title: "Root title" },
          { id: "child", parentID: "root" },
        ],
        route("child"),
      )
      dispose = setup(h.ctx as never, 10)
      await wait(150)
      expect(herdrCalls()).toEqual([["pane", "rename", "w1:p1", "Root title"]])

      h.emit("session.renamed", { sessionID: "child", title: "Child title" })
      await wait(150)
      expect(herdrCalls()).toHaveLength(1)
    } finally {
      dispose?.()
      await wait(100)
      restore()
    }
  })

  test("a session switch follows the new root, and the disposer clears the label", async () => {
    try {
      insideHerdr()
      const shown = route("root")
      const h = host(
        [
          { id: "root", title: "Root title" },
          { id: "other", title: "Other title" },
        ],
        shown,
      )
      const dispose = setup(h.ctx as never, 10)
      expect(typeof dispose).toBe("function")
      await wait(150)
      expect(herdrCalls().at(-1)).toEqual(["pane", "rename", "w1:p1", "Root title"])

      // A switch has no event; the poll must catch it.
      shown.sessionID = "other"
      await wait(150)
      expect(herdrCalls().at(-1)).toEqual(["pane", "rename", "w1:p1", "Other title"])

      dispose?.()
      await wait(150)
      expect(herdrCalls().at(-1)).toEqual(["pane", "rename", "w1:p1", "--clear"])

      // Disposed: route change and event must not rename.
      shown.sessionID = "root"
      h.emit("session.renamed", { sessionID: "other", title: "After dispose" })
      await wait(150)
      expect(herdrCalls().at(-1)).toEqual(["pane", "rename", "w1:p1", "--clear"])
    } finally {
      restore()
    }
  })

  test("deleting the shown session clears the label", async () => {
    let dispose: (() => void) | undefined
    try {
      insideHerdr()
      const h = host([{ id: "root", title: "Root title" }])
      // 60 s poll: only the handler can clear here.
      dispose = setup(h.ctx as never, 60_000)
      await wait(150)
      expect(herdrCalls().at(-1)).toEqual(["pane", "rename", "w1:p1", "Root title"])

      h.emit("session.deleted", { sessionID: "root" })
      await wait(150)
      expect(herdrCalls().at(-1)).toEqual(["pane", "rename", "w1:p1", "--clear"])
    } finally {
      dispose?.()
      await wait(100)
      restore()
    }
  })
})
