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
import { defaultHookLog, routeHookOutput, type HookDecl } from "../on-hooks-utils"

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

describe("deletedFileFromWatcher (audit-28 NOTE-8)", () => {
  test("returns the file path for an unlink watcher event", () => {
    const { deletedFileFromWatcher } = require("../on-hooks-utils") as typeof import("../on-hooks-utils")
    const file = deletedFileFromWatcher({
      type: "file.watcher.updated",
      properties: { file: ".agents/memory/latent/learnings/gone.md", event: "unlink" },
    })
    expect(file).toBe(".agents/memory/latent/learnings/gone.md")
  })

  test("returns null for add/change watcher events (only deletes matter)", () => {
    const { deletedFileFromWatcher } = require("../on-hooks-utils") as typeof import("../on-hooks-utils")
    expect(deletedFileFromWatcher({ type: "file.watcher.updated", properties: { file: "x.md", event: "add" } })).toBeNull()
    expect(deletedFileFromWatcher({ type: "file.watcher.updated", properties: { file: "x.md", event: "change" } })).toBeNull()
  })

  test("returns null for non-watcher events", () => {
    const { deletedFileFromWatcher } = require("../on-hooks-utils") as typeof import("../on-hooks-utils")
    expect(deletedFileFromWatcher({ type: "file.edited", properties: { file: "x.md" } })).toBeNull()
  })

  test("returns null for delete-like event values other than 'unlink' (documents the audit-29 gap)", () => {
    // Audit-28/29: bash-deleted notes never dispatched file.deleted in
    // opencode 1.18.26. If the real payload uses a different event value,
    // this strictness is the gap — the adapter logs rejected delete-lookalikes
    // (appendHooksLog) so a live session can capture the true shape.
    const { deletedFileFromWatcher } = require("../on-hooks-utils") as typeof import("../on-hooks-utils")
    expect(deletedFileFromWatcher({ type: "file.watcher.updated", properties: { file: "x.md", event: "remove" } })).toBeNull()
    expect(deletedFileFromWatcher({ type: "file.watcher.updated", properties: { file: "x.md", event: "delete" } })).toBeNull()
    expect(deletedFileFromWatcher({ type: "file.watcher.updated", properties: { file: "x.md" } })).toBeNull()
    expect(deletedFileFromWatcher({ type: "file.watcher.updated", properties: { event: "unlink" } })).toBeNull()
  })
})

describe("appendHooksLog (audit-29 watcher diagnostics)", () => {
  let root: string

  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), "hooks-log-"))
  })

  afterEach(() => {
    rmSync(root, { recursive: true, force: true })
  })

  test("appends a watcher-diag line to .agents/logs/hooks.log", () => {
    const { appendHooksLog } = require("../on-hooks-utils") as typeof import("../on-hooks-utils")
    appendHooksLog(root, 'watcher.rejected type=file.watcher.updated event=remove file=x.md props={}')

    const log = readFileSync(join(root, ".agents", "logs", "hooks.log"), "utf8")
    expect(log).toContain("watcher-diag")
    expect(log).toContain("watcher.rejected type=file.watcher.updated event=remove file=x.md")
  })
})
