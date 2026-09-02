// src/harnesses/opencode/hooks/on-hooks.test.ts
// Unit tests for the output-routing decision of the generic hook adapter.
//
// Regression guard: hook stdout must never reach the plugin process stderr —
// opencode surfaces plugin stderr in the TUI, which is exactly the "lint-k8s
// findings printed on top of the TUI" bug. Hook output is appended to the
// declared `log` file, or to the shared default hook log when none is declared.

import { describe, test, expect, beforeEach, afterEach } from "bun:test"
import { existsSync, mkdtempSync, readFileSync, rmSync } from "fs"
import { tmpdir } from "os"
import { join } from "path"
import { defaultHookLog, guardDecision, routeHookOutput, type HookDecl } from "../on-hooks-utils"

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
