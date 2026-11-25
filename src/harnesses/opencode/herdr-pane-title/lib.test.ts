// =============================================================================
// src/harnesses/opencode/herdr-pane-title/lib.test.ts
// Tests for the herdr pane-title plugin.
//
// Three rules matter, and each one is easy to break silently: the label follows
// the ROOT session (a subagent pane must not rename itself after a child), the
// plugin does nothing at all outside a herdr pane, and the command it runs is
// the one herdr documents.
// =============================================================================

import { afterAll, beforeAll, describe, expect, test } from "bun:test"
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { paneTitle, rootSession, type SessionInfo, type SessionSource } from "./lib"
import plugin from "./index"
import type { TuiEvent } from "./index"

function sessions(records: SessionInfo[]): SessionSource {
  const map = new Map(records.map((s) => [s.id, s]))
  return { get: (id) => map.get(id) }
}

const route = (sessionID?: string) => ({
  current: sessionID === undefined ? { name: "home" } : { name: "session", params: { sessionID } },
})

describe("rootSession", () => {
  const source = sessions([
    { id: "root", title: "Root title" },
    { id: "child", title: "Child title", parentID: "root" },
    { id: "grandchild", title: "Grandchild title", parentID: "child" },
  ])

  test("a root session is its own root", () => {
    expect(rootSession(source, "root")?.id).toBe("root")
  })

  test("a child resolves to its root, not itself", () => {
    expect(rootSession(source, "child")?.title).toBe("Root title")
  })

  test("a deep chain resolves to the root", () => {
    expect(rootSession(source, "grandchild")?.title).toBe("Root title")
  })

  test("an unknown session yields nothing", () => {
    expect(rootSession(source, "missing")).toBeUndefined()
  })

  test("a non-string id yields nothing", () => {
    expect(rootSession(source, undefined)).toBeUndefined()
  })

  test("a parentID cycle terminates instead of hanging", () => {
    const cyclic = sessions([
      { id: "a", parentID: "b" },
      { id: "b", parentID: "a" },
    ])
    expect(rootSession(cyclic, "a")).toBeUndefined()
  })
})

describe("paneTitle", () => {
  const source = sessions([
    { id: "root", title: "Root title" },
    { id: "child", title: "Child title", parentID: "root" },
    { id: "untitled", title: "" },
  ])

  test("a session route shows its root's title", () => {
    expect(paneTitle(source, route("root"))).toBe("Root title")
  })

  test("a subagent route still shows the root's title", () => {
    expect(paneTitle(source, route("child"))).toBe("Root title")
  })

  test("a non-session route leaves the label alone", () => {
    expect(paneTitle(source, route())).toBeUndefined()
  })

  test("an uncached session leaves the label alone", () => {
    expect(paneTitle(source, route("missing"))).toBeUndefined()
  })

  test("an untitled session leaves the label alone", () => {
    expect(paneTitle(source, route("untitled"))).toBeUndefined()
  })
})

describe("plugin wiring", () => {
  const KEYS = ["HERDR_ENV", "HERDR_PANE_ID", "HERDR_BIN_PATH", "PATH"] as const
  let saved: Record<string, string | undefined> = {}
  let dir: string
  let calls: string
  let stub: string

  const restoreEnv = () => {
    for (const key of KEYS) {
      if (saved[key] === undefined) delete process.env[key]
      else process.env[key] = saved[key]
    }
  }

  // A stand-in for the herdr binary: records its argv, one line per call.
  const herdrCalls = () =>
    readFileSync(calls, "utf8")
      .split("\n")
      .filter(Boolean)
      .map((line) => line.split("|"))

  // `records` is the session CACHE, which lags the events on purpose in the
  // title tests: the plugin must not depend on it having caught up.
  const fakeApi = (shown = route("root"), records: SessionInfo[] = [{ id: "root", title: "Root title" }]) => {
    const dispose: Array<() => void> = []
    const handlers = new Map<string, Array<(event: TuiEvent) => void>>()
    return {
      state: { session: sessions(records) },
      route: shown,
      event: {
        on: (type: string, handler: (event: TuiEvent) => void) => {
          handlers.set(type, [...(handlers.get(type) ?? []), handler])
          return () => handlers.set(type, (handlers.get(type) ?? []).filter((h) => h !== handler))
        },
      },
      emit: (type: string, event: TuiEvent) => {
        for (const handler of handlers.get(type) ?? []) handler(event)
      },
      lifecycle: { onDispose: (fn: () => void) => dispose.push(fn) },
      dispose,
    }
  }

  beforeAll(() => {
    saved = Object.fromEntries(KEYS.map((key) => [key, process.env[key]]))
    dir = mkdtempSync(join(tmpdir(), "herdr-pane-title-"))
    calls = join(dir, "calls")
    writeFileSync(calls, "")
    stub = join(dir, "herdr")
    process.env.HERDR_BIN_PATH = stub
    writeFileSync(
      stub,
      `#!/bin/sh\nfor a in "$@"; do printf '%s|' "$a" >> '${calls}'; done\nprintf '\\n' >> '${calls}'\n`,
      { mode: 0o755 },
    )
    chmodSync(stub, 0o755)
    writeFileSync(calls, "")
  })

  afterAll(() => {
    restoreEnv()
    rmSync(dir, { recursive: true, force: true })
  })

  test("exports the id opencode needs", () => {
    expect(plugin.id).toBe("herdr-pane-title")
    expect(typeof plugin.tui).toBe("function")
  })

  test("outside a herdr pane it does nothing", async () => {
    try {
      delete process.env.HERDR_ENV
      process.env.HERDR_PANE_ID = "w1:p1"
      process.env.HERDR_BIN_PATH = stub
      const api = fakeApi()
      await plugin.tui(api)
      expect(api.dispose).toHaveLength(0)
      await new Promise((r) => setTimeout(r, 150))
      expect(herdrCalls()).toEqual([])
    } finally {
      restoreEnv()
    }
  })

  test("an older 1.x host without the session cache is left alone", async () => {
    try {
      process.env.HERDR_ENV = "1"
      process.env.HERDR_PANE_ID = "w1:p1"
      const dispose: Array<() => void> = []
      await plugin.tui({ lifecycle: { onDispose: (fn) => dispose.push(fn) } } as never)
      expect(dispose).toHaveLength(0)
    } finally {
      restoreEnv()
    }
  })

  test("inside a herdr pane it renames the pane to the root title", async () => {
    try {
      process.env.HERDR_ENV = "1"
      process.env.HERDR_PANE_ID = "w1:p1"
      writeFileSync(calls, "")
      process.env.HERDR_BIN_PATH = stub
      const api = fakeApi()
      await plugin.tui(api)
      expect(api.dispose).toHaveLength(1)
      await new Promise((r) => setTimeout(r, 150))
      expect(herdrCalls().map((call) => call.slice(0, 4))).toEqual([
        ["pane", "rename", "w1:p1", "Root title"],
      ])
      api.dispose[0]()
      await new Promise((r) => setTimeout(r, 150))
    } finally {
      restoreEnv()
    }
  })

  test("a herdr on PATH but absent from the environment still works", async () => {
    try {
      process.env.HERDR_ENV = "1"
      process.env.HERDR_PANE_ID = "w1:p1"
      delete process.env.HERDR_BIN_PATH
      writeFileSync(calls, "")
      process.env.PATH = `${dir}:${process.env.PATH}`
      const api = fakeApi()
      await plugin.tui(api)
      await new Promise((r) => setTimeout(r, 150))
      expect(herdrCalls().map((call) => call.slice(0, 4))).toEqual([
        ["pane", "rename", "w1:p1", "Root title"],
      ])
      api.dispose[0]()
      await new Promise((r) => setTimeout(r, 150))
    } finally {
      restoreEnv()
    }
  })

  test("leaving the session route clears the label it set", async () => {
    try {
      process.env.HERDR_ENV = "1"
      process.env.HERDR_PANE_ID = "w1:p1"
      writeFileSync(calls, "")
      process.env.HERDR_BIN_PATH = stub
      const shown = route("root")
      const api = fakeApi(shown)
      await plugin.tui(api)
      await new Promise((r) => setTimeout(r, 150))

      shown.current = { name: "home" }
      await new Promise((r) => setTimeout(r, 700))
      expect(herdrCalls().map((call) => call.slice(0, 4)).at(-1)).toEqual([
        "pane",
        "rename",
        "w1:p1",
        "--clear",
      ])
      api.dispose[0]()
    } finally {
      restoreEnv()
    }
  })

  test("a title opencode assigns after creation reaches the pane title", async () => {
    // The cache has no title yet — exactly the window between `session.created`
    // and the generated title. The event carries it; the poll would be blind.
    try {
      process.env.HERDR_ENV = "1"
      process.env.HERDR_PANE_ID = "w1:p1"
      writeFileSync(calls, "")
      process.env.HERDR_BIN_PATH = stub
      const api = fakeApi(route("root"), [{ id: "root" }])
      await plugin.tui(api)
      await new Promise((r) => setTimeout(r, 150))
      expect(herdrCalls()).toEqual([])

      api.emit("session.updated", { properties: { info: { id: "root", title: "Generated later" } } })
      await new Promise((r) => setTimeout(r, 150))
      expect(herdrCalls().map((call) => call.slice(0, 4))).toEqual([
        ["pane", "rename", "w1:p1", "Generated later"],
      ])
      api.dispose[0]()
      await new Promise((r) => setTimeout(r, 150))
    } finally {
      restoreEnv()
    }
  })

  test("a rename at any point in the session is applied", async () => {
    try {
      process.env.HERDR_ENV = "1"
      process.env.HERDR_PANE_ID = "w1:p1"
      writeFileSync(calls, "")
      process.env.HERDR_BIN_PATH = stub
      const api = fakeApi()
      await plugin.tui(api)
      await new Promise((r) => setTimeout(r, 150))

      api.emit("session.updated", { properties: { info: { id: "root", title: "Renamed by hand" } } })
      await new Promise((r) => setTimeout(r, 150))
      expect(herdrCalls().map((call) => call.slice(0, 4)).at(-1)).toEqual([
        "pane",
        "rename",
        "w1:p1",
        "Renamed by hand",
      ])
      api.dispose[0]()
      await new Promise((r) => setTimeout(r, 150))
    } finally {
      restoreEnv()
    }
  })

  test("switching to another session follows the new root", async () => {
    try {
      process.env.HERDR_ENV = "1"
      process.env.HERDR_PANE_ID = "w1:p1"
      writeFileSync(calls, "")
      process.env.HERDR_BIN_PATH = stub
      const shown = route("root")
      const api = fakeApi(shown, [
        { id: "root", title: "Root title" },
        { id: "other", title: "Other title" },
      ])
      await plugin.tui(api)
      await new Promise((r) => setTimeout(r, 150))

      // No event accompanies a session switch, so this is the poll's job.
      shown.current = { name: "session", params: { sessionID: "other" } }
      await new Promise((r) => setTimeout(r, 700))
      expect(herdrCalls().map((call) => call.slice(0, 4)).at(-1)).toEqual([
        "pane",
        "rename",
        "w1:p1",
        "Other title",
      ])
      api.dispose[0]()
      await new Promise((r) => setTimeout(r, 150))
    } finally {
      restoreEnv()
    }
  })

  test("disposing clears the label it set", async () => {
    try {
      process.env.HERDR_ENV = "1"
      process.env.HERDR_PANE_ID = "w1:p1"
      writeFileSync(calls, "")
      process.env.HERDR_BIN_PATH = stub
      const api = fakeApi()
      await plugin.tui(api)
      await new Promise((r) => setTimeout(r, 150))
      api.dispose[0]()
      await new Promise((r) => setTimeout(r, 150))
      expect(herdrCalls().map((call) => call.slice(0, 4))).toEqual([
        ["pane", "rename", "w1:p1", "Root title"],
        ["pane", "rename", "w1:p1", "--clear"],
      ])
    } finally {
      restoreEnv()
    }
  })
})
