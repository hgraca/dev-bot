// src/agentic/auto-recover/hooks/opencode/on-watchdog-silent-stall.test.ts
// Unit tests for the two-strike stall decision used by the silent-stall
// watchdog. Regression guard: a busy-but-slow subagent must never be aborted
// on a single sample; only consecutive silent checks escalate to abort.

import { describe, test, expect } from "bun:test"
import { hasInFlightTool, isInFlightGeneration, stallDecision } from "./on-watchdog-silent-stall"

const CHECK_MS = 30_000

function assistantMessage(opts: { time?: Record<string, number>; parts?: unknown[] } = {}): Record<string, unknown> {
  return { info: { role: "assistant", time: opts.time ?? {} }, parts: opts.parts ?? [] }
}

describe("stallDecision", () => {
  test("first observation of a stale session logs only (watch)", () => {
    expect(stallDecision(undefined, 1_000_000, CHECK_MS)).toBe("watch")
  })

  test("still within the confirmation window waits", () => {
    expect(stallDecision(1_000_000, 1_000_000 + CHECK_MS - 1, CHECK_MS)).toBe("wait")
  })

  test("stale across consecutive checks aborts", () => {
    expect(stallDecision(1_000_000, 1_000_000 + CHECK_MS, CHECK_MS)).toBe("abort")
  })

  test("longer stalls abort", () => {
    expect(stallDecision(1_000_000, 1_000_000 + CHECK_MS * 3, CHECK_MS)).toBe("abort")
  })
})

describe("isInFlightGeneration", () => {
  test("no last message is not a generation stall", () => {
    expect(isInFlightGeneration(undefined)).toBe(false)
  })

  test("a user message is not a generation stall", () => {
    expect(isInFlightGeneration({ info: { role: "user" }, parts: [] })).toBe(false)
  })

  test("a completed assistant message is not a generation stall", () => {
    expect(
      isInFlightGeneration(
        assistantMessage({ time: { created: 1, completed: 2 } }),
      ),
    ).toBe(false)
  })

  test("an in-flight message waiting on a pending tool is not a stall", () => {
    expect(
      isInFlightGeneration(
        assistantMessage({
          parts: [{ type: "tool", state: "pending" }],
        }),
      ),
    ).toBe(false)
  })

  test("an in-flight message waiting on a running tool is not a stall", () => {
    expect(
      isInFlightGeneration(
        assistantMessage({
          parts: [{ type: "tool", state: "running" }],
        }),
      ),
    ).toBe(false)
  })

  test("an in-flight message with only text parts is a generation stall", () => {
    expect(
      isInFlightGeneration(
        assistantMessage({
          parts: [{ type: "text", text: "..." }],
        }),
      ),
    ).toBe(true)
  })

  test("an in-flight message with only completed tool parts is a stall", () => {
    expect(
      isInFlightGeneration(
        assistantMessage({
          parts: [{ type: "tool", state: "completed" }],
        }),
      ),
    ).toBe(true)
  })
})

describe("hasInFlightTool (audit-26 false positive)", () => {
  test("returns true when any recent message waits on a pending tool", () => {
    const messages = [
      { info: { role: "assistant", time: { created: 1, completed: 2 } }, parts: [] },
      { info: { role: "assistant", time: { created: 3 } }, parts: [{ type: "tool", state: "pending" }] },
    ]
    expect(hasInFlightTool(messages)).toBe(true)
  })

  test("returns true when any recent message waits on a running tool", () => {
    const messages = [
      { info: { role: "assistant", time: { created: 1, completed: 2 } }, parts: [] },
      { info: { role: "assistant", time: { created: 3 } }, parts: [{ type: "tool", state: "running" }] },
    ]
    expect(hasInFlightTool(messages)).toBe(true)
  })

  test("returns false when no tool is pending or running", () => {
    const messages = [
      { info: { role: "assistant", time: { created: 1, completed: 2 } }, parts: [{ type: "text", text: "done" }] },
      { info: { role: "assistant", time: { created: 3, completed: 4 } }, parts: [{ type: "tool", state: "completed" }] },
    ]
    expect(hasInFlightTool(messages)).toBe(false)
  })

  test("returns false for empty or non-message input", () => {
    expect(hasInFlightTool([])).toBe(false)
    expect(hasInFlightTool(undefined as unknown as any[])).toBe(false)
  })
})

describe("default stall timeout", () => {
  test("is 15 minutes (900000 ms)", async () => {
    // Guard against the default silently regressing below the audit-26 fix:
    // a subagent running a long test suite was aborted at 3 minutes.
    const file = await Bun.file(
      import.meta.dir + "/on-watchdog-silent-stall.ts",
    ).text()
    expect(file).toContain("DEV_BOT_STALL_TIMEOUT_MS || 900_000")
    expect(file).toContain("15 min")
  })
})
