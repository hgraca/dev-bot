/**
 * A per-entry mutex built on `mkdir`, which is atomic on every platform — the technique already used
 * by `src/harnesses/opencode/mcp-sync-lock.ts`, which is harness code and cannot be imported here.
 *
 * Staleness differs on purpose: that mutex guards a seconds-long critical section with a 10 s TTL,
 * while a tick can hold this lock for minutes. So the owner PID decides, the same way the harness
 * presence lock does, and the TTL is only a backstop for a PID that cannot be checked.
 */

import { mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

import { isProcessAlive } from "./lock.ts";

const OWNER_FILE = "owner";
const DEFAULT_STALE_AFTER_MS = 6 * 60 * 60 * 1000;

export interface MutexHandle {
  path: string;
  release(): void;
}

export interface MutexOptions {
  staleAfterMs?: number;
  isAlive?: (pid: number) => boolean;
  now?: () => number;
}

interface Owner {
  pid: number;
  at: number;
}

function readOwner(path: string): Owner | null {
  try {
    const raw = JSON.parse(readFileSync(join(path, OWNER_FILE), "utf8")) as unknown;
    if (raw !== null && typeof raw === "object" && Number.isInteger((raw as Owner).pid)) {
      return raw as Owner;
    }
  } catch {
    return null;
  }
  return null;
}

function isStale(path: string, options: Required<MutexOptions>): boolean {
  const owner = readOwner(path);
  if (owner) return !options.isAlive(owner.pid);
  // No readable owner: a directory left mid-creation. Fall back to its age.
  try {
    return options.now() - statSync(path).mtimeMs > options.staleAfterMs;
  } catch {
    return false;
  }
}

function tryTake(path: string, now: () => number): MutexHandle | null {
  try {
    mkdirSync(path);
  } catch {
    return null;
  }
  try {
    writeFileSync(join(path, OWNER_FILE), JSON.stringify({ pid: process.pid, at: now() }), "utf8");
  } catch {
    rmSync(path, { recursive: true, force: true });
    return null;
  }
  return {
    path,
    release() {
      rmSync(path, { recursive: true, force: true });
    },
  };
}

/** Take the mutex, reclaiming it from a dead owner once. Returns `null` when it is held. */
export function acquireMutex(path: string, options: MutexOptions = {}): MutexHandle | null {
  const resolved: Required<MutexOptions> = {
    staleAfterMs: options.staleAfterMs ?? DEFAULT_STALE_AFTER_MS,
    isAlive: options.isAlive ?? isProcessAlive,
    now: options.now ?? Date.now,
  };

  // The state directory may not exist on a first run; without it `mkdir` would fail and the tick
  // would read that as "another tick holds the lock".
  try {
    mkdirSync(dirname(path), { recursive: true });
  } catch {
    return null;
  }

  const taken = tryTake(path, resolved.now);
  if (taken) return taken;
  if (!isStale(path, resolved)) return null;

  rmSync(path, { recursive: true, force: true });
  return tryTake(path, resolved.now);
}
