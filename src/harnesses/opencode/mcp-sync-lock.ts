// src/harnesses/opencode/mcp-sync-lock.ts
// Directory mutex: mkdir is atomic everywhere.

import { mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs"
import { join } from "node:path"

const TTL_MS = 10_000
const TRIES = 20
const WAIT_MS = 10
const OWNER = "owner"

function pause(ms: number): void {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms)
}

function stale(lock: string, now: number): boolean {
  try {
    return now - statSync(lock).mtimeMs > TTL_MS
  } catch {
    return false
  }
}

function ownerOf(lock: string): string | null {
  try {
    return readFileSync(join(lock, OWNER), "utf8")
  } catch {
    return null
  }
}

/** Take the lock, retrying briefly. Returns an owner token. */
export function acquireLock(lock: string, now: () => number = Date.now): string | null {
  const token = `${process.pid}-${Math.random().toString(36).slice(2)}`
  for (let i = 0; i < TRIES; i += 1) {
    try {
      mkdirSync(lock)
      writeFileSync(join(lock, OWNER), token, "utf8")
      return token
    } catch (err) {
      if ((err as { code?: string }).code !== "EEXIST") return null
      // A crashed holder must not wedge the lock.
      if (stale(lock, now())) rmSync(lock, { recursive: true, force: true })
      pause(WAIT_MS)
    }
  }
  return null
}

/** Release only the lock this token still owns. */
export function releaseLock(lock: string, token: string): void {
  // Reclaimed lock is not ours: never remove it.
  if (ownerOf(lock) !== token) return
  rmSync(lock, { recursive: true, force: true })
}
