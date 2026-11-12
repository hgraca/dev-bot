import { afterEach, describe, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { acquireMutex } from "./mutex.ts";

const dirs: string[] = [];

function sandbox(): string {
  const dir = mkdtempSync(join(tmpdir(), "autobot-mutex-"));
  dirs.push(dir);
  return join(dir, "tick.lock");
}

afterEach(() => {
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});

describe("acquireMutex", () => {
  test("takes a free mutex and releases it", () => {
    const path = sandbox();
    const handle = acquireMutex(path);
    expect(handle).not.toBeNull();
    expect(existsSync(join(path, "owner"))).toBe(true);
    handle?.release();
    expect(existsSync(path)).toBe(false);
  });

  test("creates a missing parent directory", () => {
    const nested = join(sandbox(), "state", "autobot", "tick.lock");
    const handle = acquireMutex(nested);
    expect(handle).not.toBeNull();
    handle?.release();
  });

  test("refuses a mutex held by a live owner", () => {
    const path = sandbox();
    const first = acquireMutex(path);
    expect(first).not.toBeNull();
    expect(acquireMutex(path)).toBeNull();
  });

  test("reclaims a mutex whose owner is gone", () => {
    const path = sandbox();
    mkdirSync(path);
    writeFileSync(join(path, "owner"), JSON.stringify({ pid: 999999, at: Date.now() }));

    const handle = acquireMutex(path, { isAlive: () => false });
    expect(handle).not.toBeNull();
  });

  test("does not reclaim a mutex whose owner is alive", () => {
    const path = sandbox();
    mkdirSync(path);
    writeFileSync(join(path, "owner"), JSON.stringify({ pid: 42, at: Date.now() }));

    expect(acquireMutex(path, { isAlive: () => true })).toBeNull();
  });

  test("reclaims an ownerless directory past the backstop", () => {
    const path = sandbox();
    mkdirSync(path);

    const handle = acquireMutex(path, {
      staleAfterMs: 1000,
      now: () => Date.now() + 5000,
    });
    expect(handle).not.toBeNull();
  });

  test("keeps an ownerless directory inside the backstop", () => {
    const path = sandbox();
    mkdirSync(path);

    expect(
      acquireMutex(path, { staleAfterMs: 60_000, now: () => Date.now() }),
    ).toBeNull();
  });
});
