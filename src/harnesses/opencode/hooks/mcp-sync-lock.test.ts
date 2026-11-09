// Mutex tests: ownership and stale reclaim.

import { afterEach, describe, expect, test } from "bun:test"
import { existsSync, mkdtempSync, rmSync, utimesSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { acquireLock, releaseLock } from "../mcp-sync-lock"

let dir = ""

function lockPath(): string {
  dir = mkdtempSync(join(tmpdir(), "mcp-sync-lock-"))
  return join(dir, "config.lock")
}

afterEach(() => {
  if (dir) rmSync(dir, { recursive: true, force: true })
  dir = ""
})

describe("acquireLock", () => {
  test("grants the lock once and refuses a second holder", () => {
    const lock = lockPath()
    const token = acquireLock(lock)
    expect(token).not.toBeNull()
    expect(acquireLock(lock)).toBeNull()
    releaseLock(lock, token as string)
    const again = acquireLock(lock)
    expect(again).not.toBeNull()
    releaseLock(lock, again as string)
  })

  test("reclaims a lock left behind by a crashed session", () => {
    const lock = lockPath()
    const token = acquireLock(lock)
    const old = new Date(Date.now() - 60_000)
    utimesSync(lock, old, old)
    const next = acquireLock(lock)
    expect(next).not.toBeNull()
    expect(next).not.toBe(token)
    releaseLock(lock, next as string)
    expect(existsSync(lock)).toBe(false)
  })

  test("fails when the path cannot be created", () => {
    expect(acquireLock("/proc/definitely-not-writable/config.lock")).toBeNull()
  })
})

describe("releaseLock", () => {
  test("a stale holder must not remove a replacement lock", () => {
    const lock = lockPath()
    const first = acquireLock(lock) as string
    const old = new Date(Date.now() - 60_000)
    utimesSync(lock, old, old)
    const second = acquireLock(lock) as string

    // A paused holder must not remove the new lock.
    releaseLock(lock, first)
    expect(existsSync(lock)).toBe(true)
    expect(acquireLock(lock)).toBeNull()

    releaseLock(lock, second)
    expect(existsSync(lock)).toBe(false)
  })

  test("is a no-op on a lock it never held", () => {
    expect(() => releaseLock(join(tmpdir(), "never-taken.lock"), "x")).not.toThrow()
  })
})
