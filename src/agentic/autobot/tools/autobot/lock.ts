/**
 * Presence check for a running devbot harness.
 *
 * The harness writes one file per process at `<devbot_dir>/state/devbot/<pid>.json` and removes it on
 * exit. Liveness is decided by the PID, not by a timestamp: a file whose process is gone is ignored,
 * so a crash leaves only tidy-up work, never a false "devbot is running".
 *
 * One file per PID rather than a single lock file: two sessions in the same project would otherwise
 * overwrite each other, and the first to exit would delete the second's lock.
 *
 * `kind` separates a human session (`session`) from AutoBot's own runs (`autobot`), so the guard is
 * not trivially satisfied by the ticks it is gating.
 */

import { readdirSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";

export interface SessionLock {
  pid: number;
  kind: string;
  project?: string;
  harness?: string;
  started_at?: string;
}

/** True when the process exists. Permission errors still mean it exists. */
export function isProcessAlive(pid: number): boolean {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === "EPERM";
  }
}

interface LockFile {
  path: string;
  lock: SessionLock;
}

function readLockFiles(stateDir: string): LockFile[] {
  let entries: string[];
  try {
    entries = readdirSync(stateDir);
  } catch {
    return [];
  }
  const files: LockFile[] = [];
  for (const entry of entries) {
    if (!entry.endsWith(".json")) continue;
    const path = join(stateDir, entry);
    try {
      const raw = JSON.parse(readFileSync(path, "utf8")) as unknown;
      if (raw !== null && typeof raw === "object" && Number.isInteger((raw as SessionLock).pid)) {
        files.push({ path, lock: raw as SessionLock });
      }
    } catch {
      continue;
    }
  }
  return files;
}

/** Every well-formed lock file in the directory; a torn or hand-edited file is skipped. */
export function readLocks(stateDir: string): SessionLock[] {
  return readLockFiles(stateDir).map((file) => file.lock);
}

/**
 * Remove lock files whose process is gone. Reading ignores them anyway; this keeps the directory from
 * growing a file per crash.
 */
export function sweepDeadLocks(
  stateDir: string,
  isAlive: (pid: number) => boolean = isProcessAlive,
  remove: (path: string) => void = (path) => rmSync(path, { force: true }),
): string[] {
  const removed: string[] = [];
  for (const file of readLockFiles(stateDir)) {
    if (isAlive(file.lock.pid)) continue;
    try {
      remove(file.path);
      removed.push(file.path);
    } catch {
      continue;
    }
  }
  return removed;
}

/** Locks left by a harness that is still running, ignoring AutoBot's own runs. */
export function liveSessionLocks(
  stateDir: string,
  isAlive: (pid: number) => boolean = isProcessAlive,
): SessionLock[] {
  return readLocks(stateDir).filter((lock) => lock.kind === "session" && isAlive(lock.pid));
}

/** True when a human-driven devbot harness is running in the project. */
export function projectHasRunningDevbot(
  stateDir: string,
  isAlive: (pid: number) => boolean = isProcessAlive,
): boolean {
  return liveSessionLocks(stateDir, isAlive).length > 0;
}
