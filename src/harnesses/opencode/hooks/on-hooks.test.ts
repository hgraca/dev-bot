// src/harnesses/opencode/hooks/on-hooks.test.ts
// Unit tests for the output-routing decision of the generic hook adapter.
//
// Regression guard: hook stdout must never reach the plugin process stderr —
// opencode surfaces plugin stderr in the TUI, which is exactly the "lint-k8s
// findings printed on top of the TUI" bug. Hook output is appended to the
// declared `log` file, or to the shared default hook log when none is declared.

import { describe, test, expect, beforeEach, afterEach } from "bun:test"
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs"
import { tmpdir } from "os"
import { join } from "path"
import {
  createFileEditGate,
  defaultHookLog,
  guardDecision,
  resolveGlobalConfigPath,
  routeHookOutput,
  type HookDecl,
} from "../on-hooks-utils"

const LOG = ".agents/logs/lint-k8s.log"

function hook(overrides: Partial<HookDecl> = {}): HookDecl {
  return { id: "lint-k8s", event: "file.edited", run: ["bash", "lint.sh"], ...overrides }
}

// Capture everything written to process.stderr while fn runs.
function captureStderr(fn: () => void): string[] {
  const writes: string[] = []
  const original = process.stderr.write.bind(process.stderr)
  process.stderr.write = ((chunk: unknown) => {
    writes.push(String(chunk))
    return true
  }) as typeof process.stderr.write
  try {
    fn()
  } finally {
    process.stderr.write = original
  }
  return writes
}

describe("routeHookOutput", () => {
  let root: string

  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), "on-hooks-test-"))
  })

  afterEach(() => {
    rmSync(root, { recursive: true, force: true })
  })

  test("writes non-empty stdout to the declared log file with timestamp and hook id", () => {
    routeHookOutput({ stdout: 'container "nginx" has memory limit 0\n', stderr: "" }, hook({ log: LOG }), root)

    const path = join(root, LOG)
    expect(existsSync(path)).toBe(true)
    const content = readFileSync(path, "utf8")
    expect(content).toMatch(/^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\] lint-k8s\n/)
    expect(content).toContain('container "nginx" has memory limit 0')
  })

  test("appends non-empty stderr to the log file labeled [stderr]", () => {
    routeHookOutput({ stdout: "ok\n", stderr: "warning: x\n" }, hook({ log: LOG }), root)

    const content = readFileSync(join(root, LOG), "utf8")
    expect(content).toContain("ok")
    expect(content).toContain("[stderr]\nwarning: x")
  })

  test("never emits hook output to process stderr (TUI leak regression)", () => {
    const writes = captureStderr(() => {
      routeHookOutput({ stdout: "violation\n", stderr: "warn\n" }, hook({ log: LOG }), root)
      routeHookOutput({ stdout: "noise\n", stderr: "" }, hook({}), root)
    })

    expect(writes).toEqual([])
  })

  test("routes stdout to the default hook log when no log file is declared", () => {
    routeHookOutput({ stdout: "violation\n", stderr: "" }, hook({}), root)

    const path = join(root, defaultHookLog())
    expect(existsSync(path)).toBe(true)
    const content = readFileSync(path, "utf8")
    expect(content).toContain("lint-k8s")
    expect(content).toContain("violation")
  })

  test("writes nothing for whitespace-only stdout and stderr", () => {
    routeHookOutput({ stdout: "   \n\t\n", stderr: "  \n" }, hook({ log: LOG }), root)

    expect(existsSync(join(root, ".agents"))).toBe(false)
  })
})

// ── guardDecision (audit-31 §2: blocking guard fails closed) ────────────────

describe("guardDecision", () => {
  test("blocking guard with explicit blocked:true denies with the guard message", () => {
    const d = guardDecision({ stdout: '{"blocked":true,"message":"rm -rf is blocked"}', stderr: "", exitCode: 0 }, true)
    expect(d.blocked).toBe(true)
    expect(d.message).toBe("rm -rf is blocked")
  })

  test("blocking guard that allows emits no block", () => {
    const d = guardDecision({ stdout: '{"blocked":false}', stderr: "", exitCode: 0 }, true)
    expect(d.blocked).toBe(false)
  })

  test("blocking guard with non-zero exit denies (guard errored)", () => {
    const d = guardDecision({ stdout: "", stderr: "bun: command not found", exitCode: 127 }, true)
    expect(d.blocked).toBe(true)
    expect(d.message).toContain("guard temporarily unavailable")
  })

  test("blocking guard with unparseable output denies (fail closed)", () => {
    const d = guardDecision({ stdout: "not json at all", stderr: "", exitCode: 0 }, true)
    expect(d.blocked).toBe(true)
    expect(d.message).toContain("guard temporarily unavailable")
  })

  test("non-blocking hook with non-zero exit does not deny", () => {
    const d = guardDecision({ stdout: "", stderr: "boom", exitCode: 3 }, false)
    expect(d.blocked).toBe(false)
  })

  test("non-blocking hook with garbage output does not deny", () => {
    const d = guardDecision({ stdout: "noise", stderr: "", exitCode: 0 }, false)
    expect(d.blocked).toBe(false)
  })

  test("non-blocking hook with explicit blocked:true still denies", () => {
    const d = guardDecision({ stdout: '{"blocked":true,"message":"rule"}', stderr: "", exitCode: 0 }, false)
    expect(d.blocked).toBe(true)
  })
})

// ── resolveGlobalConfigPath (audit-32 FAIL: guards not enforced live) ────────
// The harness exports DEV_BOT_ROOT, not DEVBOT_ROOT; the plugin reads env
// DEVBOT_ROOT and got "" → --global-config "" → no guard rules. Resolution
// must prefer the plugin's own root (realpath, beside .devbot.global.jsonc),
// then fall back to env DEV_BOT_ROOT.

describe("resolveGlobalConfigPath", () => {
  let root: string

  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), "global-config-test-"))
  })

  afterEach(() => {
    rmSync(root, { recursive: true, force: true })
  })

  test("prefers .devbot.global.jsonc beside the plugin root", () => {
    writeFileSync(join(root, ".devbot.global.jsonc"), "{}")
    const result = resolveGlobalConfigPath(root, {})
    expect(result).toBe(join(root, ".devbot.global.jsonc"))
  })

  test("falls back to env DEV_BOT_ROOT when no config beside plugin root", () => {
    const envRoot = mkdtempSync(join(tmpdir(), "global-config-env-"))
    writeFileSync(join(envRoot, ".devbot.global.jsonc"), "{}")
    try {
      const result = resolveGlobalConfigPath(root, { DEV_BOT_ROOT: envRoot })
      expect(result).toBe(join(envRoot, ".devbot.global.jsonc"))
    } finally {
      rmSync(envRoot, { recursive: true, force: true })
    }
  })

  test("ignores env DEVBOT_ROOT (wrong spelling, never exported)", () => {
    const result = resolveGlobalConfigPath(root, { DEVBOT_ROOT: "/somewhere" })
    expect(result).toBe("")
  })

  test("returns empty string when no config and no env fallback", () => {
    const result = resolveGlobalConfigPath(root, {})
    expect(result).toBe("")
  })
})

// ── createFileEditGate (audit-32 FAIL: format-yml burst-edit race) ───────────
// Two file.edited events within ~1s spawned two concurrent format-hook runs;
// their read-modify-write interleaves corrupted the file. The gate serializes
// per file: one in-flight run at a time, and edits landing mid-run are
// coalesced into a single trailing re-run of the same stored run (which
// re-reads the file's latest content — exactly what a formatter needs).

describe("createFileEditGate", () => {
  test("never runs the same file concurrently; burst collapses to one trailing run", async () => {
    const gate = createFileEditGate()
    let started = 0
    let maxConcurrent = 0
    let inFlight = 0
    let release!: () => void
    const hold = new Promise<void>((res) => {
      release = res
    })

    const run = async () => {
      started++
      inFlight++
      maxConcurrent = Math.max(maxConcurrent, inFlight)
      await hold // hold every run open so bursts overlap the in-flight one
      inFlight--
    }

    // Burst of three edits while the first run is still in flight.
    gate("a.yml", run)
    gate("a.yml", run)
    gate("a.yml", run)

    await new Promise((r) => setTimeout(r, 5))
    expect(started).toBe(1) // only the first run started
    expect(maxConcurrent).toBe(1)

    release()
    await new Promise((r) => setTimeout(r, 10))
    // One trailing coalesced re-run — three edits do NOT become three runs.
    expect(started).toBe(2)
    expect(maxConcurrent).toBe(1)
  })

  test("a second edit after the run settled starts a fresh run", async () => {
    const gate = createFileEditGate()
    const runs: string[] = []
    let release!: () => void
    const hold = new Promise<void>((res) => {
      release = res
    })

    const run = async () => {
      runs.push("start")
      await hold
      runs.push("end")
    }

    gate("a.yml", run)
    release()
    await new Promise((r) => setTimeout(r, 5))

    // Run settled; a later event must start a new run, not be lost.
    gate("a.yml", run)
    release()
    await new Promise((r) => setTimeout(r, 5))

    expect(runs).toEqual(["start", "end", "start", "end"])
  })

  test("different files run independently", async () => {
    const gate = createFileEditGate()
    const order: string[] = []
    let releaseA!: () => void
    const holdA = new Promise<void>((res) => {
      releaseA = res
    })

    gate("a.yml", async () => {
      order.push("a-start")
      await holdA
      order.push("a-end")
    })
    gate("b.yml", async () => {
      order.push("b-done")
    })

    await new Promise((r) => setTimeout(r, 5))
    expect(order).toEqual(["a-start", "b-done"]) // b is not blocked by a
    releaseA()
    await new Promise((r) => setTimeout(r, 5))
    expect(order).toEqual(["a-start", "b-done", "a-end"])
  })

  test("a failing run does not wedge the file gate", async () => {
    const gate = createFileEditGate()
    let started = 0
    let release!: () => void
    const hold = new Promise<void>((res) => {
      release = res
    })

    const run = async () => {
      started++
      await hold
      throw new Error("hook boom")
    }

    gate("a.yml", run)
    gate("a.yml", run) // coalesced edit while the failing run is in flight
    release()
    await new Promise((r) => setTimeout(r, 10))

    // The dirty edit still gets its trailing run despite the failure.
    expect(started).toBe(2)
  })
})
