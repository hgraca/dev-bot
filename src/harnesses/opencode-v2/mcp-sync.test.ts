// src/harnesses/opencode-v2/mcp-sync.test.ts
// Runtime MCP sync decisions (./mcp-sync-utils.ts).
// Covers the 2.3 list envelope and the transition-only rule.

import { describe, expect, test } from "bun:test"
import {
  desiredDisabled,
  devbotDirFromConfig,
  planWrites,
  projectRootCandidates,
  resolveProjectRoot,
  serversFrom,
  statusMap,
  statusOf,
  summary,
} from "./mcp-sync-utils"

const server = (name: string, status: string) => ({ name, status: { status } })

describe("serversFrom", () => {
  test("reads the 2.3 envelope: { location, data }", () => {
    expect(serversFrom({ location: { directory: "/p" }, data: [server("a", "connected")] })).toEqual([
      server("a", "connected"),
    ])
  })

  test("tolerates a bare array", () => {
    expect(serversFrom([server("a", "connected")])).toHaveLength(1)
  })

  test("tolerates the older { servers } and { data: { servers } } wrappers", () => {
    expect(serversFrom({ servers: [server("a", "connected")] })).toHaveLength(1)
    expect(serversFrom({ data: { servers: [server("a", "connected")] } })).toHaveLength(1)
  })

  test("an unknown envelope yields no servers, not a crash", () => {
    expect(serversFrom(undefined)).toEqual([])
    expect(serversFrom({ data: null })).toEqual([])
    expect(serversFrom({ data: {} })).toEqual([])
  })
})

describe("statusOf", () => {
  test("reads the nested status object", () => {
    expect(statusOf(server("a", "connected"))).toBe("connected")
  })

  test("reads a bare status string", () => {
    expect(statusOf({ name: "a", status: "disabled" })).toBe("disabled")
  })

  test("missing status is empty, never a false 'connected'", () => {
    expect(statusOf(undefined)).toBe("")
    expect(statusOf({ name: "a" })).toBe("")
  })
})

describe("desiredDisabled", () => {
  test("connected and disabled are user intent", () => {
    expect(desiredDisabled("connected")).toBe(false)
    expect(desiredDisabled("disabled")).toBe(true)
  })

  test.each(["failed", "needs_auth", "pending", "unknown", ""])(
    "%s is not user intent — no write",
    (status) => {
      expect(desiredDisabled(status)).toBeNull()
    },
  )
})

describe("planWrites", () => {
  const baseline = statusMap([server("a", "connected"), server("b", "connected")])

  test("the first poll seeds a baseline and never writes", () => {
    expect(planWrites(null, [server("a", "disabled")])).toEqual([])
  })

  test("no transition means no write", () => {
    expect(
      planWrites(baseline, [server("a", "connected"), server("b", "connected")]),
    ).toEqual([])
  })

  test("a toggle is written in the config's inverted form", () => {
    expect(planWrites(baseline, [server("a", "disabled"), server("b", "connected")])).toEqual([
      { name: "a", disabled: true },
    ])
    expect(planWrites(baseline, [server("a", "connected"), server("b", "disabled")])).toEqual([
      { name: "b", disabled: true },
    ])
  })

  test("re-enabling writes disabled:false", () => {
    const off = statusMap([server("a", "disabled")])
    expect(planWrites(off, [server("a", "connected")])).toEqual([{ name: "a", disabled: false }])
  })

  test("a transition into failed/needs_auth is not an instruction", () => {
    expect(planWrites(baseline, [server("a", "failed"), server("b", "needs_auth")])).toEqual([])
  })

  test("a new server appearing is not a toggle", () => {
    expect(planWrites(baseline, [server("a", "connected"), server("c", "disabled")])).toEqual([
      { name: "c", disabled: true },
    ])
  })

  test("entries without a name are ignored", () => {
    expect(planWrites(baseline, [{ status: { status: "disabled" } }])).toEqual([])
  })
})

describe("statusMap / summary", () => {
  test("keys by name and summarises in a stable order", () => {
    const map = statusMap([server("b", "disabled"), server("a", "connected")])
    expect([...map.keys()]).toEqual(["b", "a"])
    expect(summary(map)).toBe("a=connected, b=disabled")
  })
})

describe("devbotDirFromConfig", () => {
  test("reads the configured devbot dir", () => {
    expect(devbotDirFromConfig({ devbot_dir: ".vault" })).toBe(".vault")
  })

  test("defaults to .agents when the key is absent", () => {
    expect(devbotDirFromConfig({})).toBe(".agents")
    expect(devbotDirFromConfig(undefined)).toBe(".agents")
    expect(devbotDirFromConfig({ devbot_dir: "" })).toBe(".agents")
    expect(devbotDirFromConfig({ devbot_dir: 7 })).toBe(".agents")
  })
})

// ── Project root resolution (audit-01 FAIL-2) ────────────────────────────────
// A plugin set loaded for an ancestor project resolved `project.canonical` to
// that ancestor, so the sync rewrote the ancestor's opencode.jsonc and never
// touched the session's own project. The session location is the only target;
// a load-time project is a signal, never a fallback (review r4620826453).

describe("projectRootCandidates", () => {
  test("orders session directory, then load-time project, then cwd", () => {
    const location = { directory: "/work/nested", project: { canonical: "/work" } }
    expect(projectRootCandidates(location, "/work/nested")).toEqual(["/work/nested", "/work"])
  })

  test("drops empty values so an absent key cannot outrank a present one", () => {
    expect(projectRootCandidates({ directory: "  ", project: { canonical: "/work" } }, "/x")).toEqual([
      "/work",
      "/x",
    ])
  })

  test("tolerates a missing location envelope", () => {
    expect(projectRootCandidates(undefined, "/x")).toEqual(["/x"])
  })

  test("de-duplicates a cwd that is already the session directory", () => {
    expect(projectRootCandidates({ directory: "/work/nested" }, "/work/nested")).toEqual(["/work/nested"])
  })
})

describe("resolveProjectRoot", () => {
  const devbot = (dir: string) => dir === "/work/nested" || dir === "/work"

  test("uses the session directory", () => {
    expect(resolveProjectRoot({ directory: "/work/nested", project: { canonical: "/work" } }, "/x", devbot)).toBe(
      "/work/nested",
    )
  })

  test("never falls back to a valid ancestor when the directory is invalid", () => {
    // The nested/shared-server case: writing to /work is the bug.
    const location = { directory: "/work/nested", project: { canonical: "/work" } }
    expect(resolveProjectRoot(location, "/x", (dir) => dir === "/work")).toBe("")
  })

  test("uses the load-time project only when the host omits the directory", () => {
    expect(resolveProjectRoot({ project: { canonical: "/work" } }, "/x", devbot)).toBe("/work")
  })

  test("falls back to cwd when the envelope carries no project at all", () => {
    expect(resolveProjectRoot(undefined, "/work/nested", devbot)).toBe("/work/nested")
  })

  test("answers an empty string when nothing is a dev-bot project", () => {
    expect(resolveProjectRoot({ directory: "/work/nested" }, "/x", () => false)).toBe("")
  })

  test("trims a padded directory", () => {
    expect(resolveProjectRoot({ directory: " /work/nested " }, "/x", devbot)).toBe("/work/nested")
  })
})
