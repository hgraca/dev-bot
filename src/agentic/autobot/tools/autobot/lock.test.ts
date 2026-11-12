import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  isProcessAlive,
  liveSessionLocks,
  projectHasRunningDevbot,
  readLocks,
  sweepDeadLocks,
} from "./lock.ts";

const dirs: string[] = [];

function stateDir(): string {
  const dir = mkdtempSync(join(tmpdir(), "autobot-lock-"));
  dirs.push(dir);
  return dir;
}

function writeLock(dir: string, name: string, body: unknown): void {
  writeFileSync(join(dir, name), typeof body === "string" ? body : JSON.stringify(body));
}

afterEach(() => {
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});

describe("isProcessAlive", () => {
  test("sees the current process", () => {
    expect(isProcessAlive(process.pid)).toBe(true);
  });

  test("sees a process that has exited", async () => {
    const child = Bun.spawn(["true"], { stdio: ["ignore", "ignore", "ignore"] });
    const pid = child.pid;
    await child.exited;
    expect(isProcessAlive(pid)).toBe(false);
  });

  test("rejects nonsense pids", () => {
    expect(isProcessAlive(0)).toBe(false);
    expect(isProcessAlive(-1)).toBe(false);
    expect(isProcessAlive(1.5)).toBe(false);
  });
});

describe("readLocks", () => {
  test("returns nothing for a missing directory", () => {
    expect(readLocks(join(stateDir(), "absent"))).toEqual([]);
  });

  test("reads well-formed locks", () => {
    const dir = stateDir();
    writeLock(dir, "100.json", { pid: 100, kind: "session" });
    writeLock(dir, "101.json", { pid: 101, kind: "autobot" });
    expect(readLocks(dir)).toHaveLength(2);
  });

  test("skips malformed, torn and non-JSON files", () => {
    const dir = stateDir();
    writeLock(dir, "100.json", { pid: 100, kind: "session" });
    writeLock(dir, "broken.json", "{ not json");
    writeLock(dir, "nopid.json", { kind: "session" });
    writeLock(dir, "notes.txt", "ignore me");
    expect(readLocks(dir).map((lock) => lock.pid)).toEqual([100]);
  });
});

describe("liveSessionLocks", () => {
  test("keeps only live human sessions", () => {
    const dir = stateDir();
    writeLock(dir, "1.json", { pid: 1, kind: "session" });
    writeLock(dir, "2.json", { pid: 2, kind: "autobot" });
    writeLock(dir, "3.json", { pid: 3, kind: "session" });

    const alive = (pid: number) => pid !== 3;
    expect(liveSessionLocks(dir, alive).map((lock) => lock.pid)).toEqual([1]);
  });

  test("ignores a lock whose process is gone", () => {
    const dir = stateDir();
    writeLock(dir, "1.json", { pid: 1, kind: "session" });
    expect(liveSessionLocks(dir, () => false)).toEqual([]);
  });
});

describe("projectHasRunningDevbot", () => {
  test("is false for an empty project", () => {
    expect(projectHasRunningDevbot(stateDir(), () => true)).toBe(false);
  });

  test("is true for a live human session", () => {
    const dir = stateDir();
    writeLock(dir, "1.json", { pid: 1, kind: "session" });
    expect(projectHasRunningDevbot(dir, (pid) => pid === 1)).toBe(true);
  });

  test("is false when only AutoBot's own runs are alive", () => {
    const dir = stateDir();
    writeLock(dir, "1.json", { pid: 1, kind: "autobot" });
    expect(projectHasRunningDevbot(dir, () => true)).toBe(false);
  });

  test("is false when the session process has exited", () => {
    const dir = stateDir();
    writeLock(dir, "1.json", { pid: 1, kind: "session" });
    expect(projectHasRunningDevbot(dir, () => false)).toBe(false);
  });
});

describe("sweepDeadLocks", () => {
  test("removes only the locks whose process is gone", () => {
    const dir = stateDir();
    writeLock(dir, "1.json", { pid: 1, kind: "session" });
    writeLock(dir, "2.json", { pid: 2, kind: "autobot" });

    const removed = sweepDeadLocks(dir, (pid) => pid === 1);

    expect(removed).toHaveLength(1);
    expect(removed[0]).toContain("2.json");
    expect(readLocks(dir).map((lock) => lock.pid)).toEqual([1]);
  });

  test("removes nothing when every process is alive", () => {
    const dir = stateDir();
    writeLock(dir, "1.json", { pid: 1, kind: "session" });
    expect(sweepDeadLocks(dir, () => true)).toEqual([]);
    expect(readLocks(dir)).toHaveLength(1);
  });

  test("copes with a missing directory", () => {
    expect(sweepDeadLocks(join(stateDir(), "absent"), () => false)).toEqual([]);
  });

  test("skips a file it cannot remove and keeps going", () => {
    const dir = stateDir();
    writeLock(dir, "1.json", { pid: 1, kind: "session" });
    writeLock(dir, "2.json", { pid: 2, kind: "session" });
    const removed = sweepDeadLocks(dir, () => false, (path) => {
      if (path.endsWith("1.json")) throw new Error("busy");
    });
    expect(removed).toHaveLength(1);
    expect(removed[0]).toContain("2.json");
  });
});
