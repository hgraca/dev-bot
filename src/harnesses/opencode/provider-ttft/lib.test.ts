// Tests for the pure logic of provider-ttft.
// The state machine is the whole risk surface.

import { describe, expect, test } from "bun:test"
import { formatTtft, recordAssistantMessage, takeFirstDelta, withTtft } from "./lib"

const assistant = (overrides = {}) => ({
  id: "msg_1",
  role: "assistant",
  time: { created: 1_000 },
  ...overrides,
})

describe("recordAssistantMessage", () => {
  test("records the created time of an in-flight assistant message", () => {
    const pending = new Map()
    recordAssistantMessage(pending, assistant())

    expect(pending.get("msg_1")).toEqual({ created: 1_000 })
  })

  test("ignores user messages", () => {
    const pending = new Map()
    recordAssistantMessage(pending, assistant({ role: "user" }))

    expect(pending.size).toBe(0)
  })

  test("ignores a message with no start time", () => {
    const pending = new Map()
    recordAssistantMessage(pending, assistant({ time: {} }))

    expect(pending.size).toBe(0)
  })

  test("keeps the original start time across later updates", () => {
    const pending = new Map()
    recordAssistantMessage(pending, assistant())
    recordAssistantMessage(pending, assistant({ time: { created: 9_999 } }))

    expect(pending.get("msg_1")).toEqual({ created: 1_000 })
  })

  test("drops a request that completed without a delta", () => {
    const pending = new Map()
    recordAssistantMessage(pending, assistant())
    recordAssistantMessage(pending, assistant({ time: { created: 1_000, completed: 4_000 } }))

    expect(pending.size).toBe(0)
  })
})

describe("takeFirstDelta", () => {
  test("returns the elapsed time for the first delta", () => {
    const pending = new Map()
    recordAssistantMessage(pending, assistant())

    expect(takeFirstDelta(pending, "msg_1", 1_250)).toBe(250)
  })

  test("returns undefined for deltas after the first", () => {
    const pending = new Map()
    recordAssistantMessage(pending, assistant())
    takeFirstDelta(pending, "msg_1", 1_250)

    expect(takeFirstDelta(pending, "msg_1", 1_400)).toBeUndefined()
  })

  test("does not re-arm a request that already reported", () => {
    const pending = new Map()
    recordAssistantMessage(pending, assistant())
    expect(takeFirstDelta(pending, "msg_1", 1_250)).toBe(250)

    recordAssistantMessage(pending, assistant())

    expect(takeFirstDelta(pending, "msg_1", 30_000)).toBeUndefined()
  })

  test("returns undefined for an untracked message", () => {
    const pending = new Map()

    expect(takeFirstDelta(pending, "msg_unknown", 1_250)).toBeUndefined()
  })

  test("returns undefined when the clocks disagree", () => {
    const pending = new Map()
    recordAssistantMessage(pending, assistant({ time: { created: 5_000 } }))

    expect(takeFirstDelta(pending, "msg_1", 1_000)).toBeUndefined()
  })

  test("tracks two concurrent requests independently", () => {
    const pending = new Map()
    recordAssistantMessage(pending, assistant({ id: "a", time: { created: 1_000 } }))
    recordAssistantMessage(pending, assistant({ id: "b", time: { created: 2_000 } }))

    expect(takeFirstDelta(pending, "b", 3_000)).toBe(1_000)
    expect(takeFirstDelta(pending, "a", 3_500)).toBe(2_500)
  })
})

describe("withTtft", () => {
  test("records a reading per session", () => {
    expect(withTtft(new Map(), "ses_a", 1_200).get("ses_a")).toBe(1_200)
  })

  test("replaces the value for the same session", () => {
    const next = withTtft(withTtft(new Map(), "ses_a", 1_200), "ses_a", 900)

    expect(next.get("ses_a")).toBe(900)
    expect(next.size).toBe(1)
  })

  test("does not mutate the input map", () => {
    const before = new Map()
    withTtft(before, "ses_a", 1_200)

    expect(before.size).toBe(0)
  })

  test("evicts the oldest session past the cap", () => {
    let readings = new Map()
    readings = withTtft(readings, "a", 1, 2)
    readings = withTtft(readings, "b", 2, 2)
    readings = withTtft(readings, "c", 3, 2)

    expect([...readings.keys()]).toEqual(["b", "c"])
  })
})

describe("formatTtft", () => {
  test("renders sub-second times with one decimal", () => {
    expect(formatTtft(840)).toBe("0.8s")
  })

  test("renders seconds with one decimal", () => {
    expect(formatTtft(1_234)).toBe("1.2s")
    expect(formatTtft(12_345)).toBe("12.3s")
  })
})
