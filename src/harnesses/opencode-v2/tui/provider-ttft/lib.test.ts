// src/harnesses/opencode-v2/tui/provider-ttft/lib.test.ts
// TTFT maths (./lib.ts), independent of the host.

import { describe, expect, test } from "bun:test"
import { firstTokenMs, formatTtft, withTtft } from "./lib"

describe("firstTokenMs", () => {
  test("difference between the recorded stamps", () => {
    expect(firstTokenMs({ type: "assistant", time: { created: 1000, firstToken: 1800 } })).toBe(800)
  })

  test("no first token yet is undefined, not 0", () => {
    expect(firstTokenMs({ type: "assistant", time: { created: 1000 } })).toBeUndefined()
  })

  test("no created stamp is undefined", () => {
    expect(firstTokenMs({ type: "assistant", time: { firstToken: 1800 } })).toBeUndefined()
  })

  test("a user message carries no TTFT", () => {
    expect(firstTokenMs({ type: "user", time: { created: 1000, firstToken: 1800 } })).toBeUndefined()
  })

  test("v1's `role` field is accepted too", () => {
    expect(firstTokenMs({ role: "assistant", time: { created: 1000, firstToken: 1500 } })).toBe(500)
    expect(firstTokenMs({ role: "user", time: { created: 1000, firstToken: 1500 } })).toBeUndefined()
  })

  test("a clock that goes backwards is not a negative TTFT", () => {
    expect(firstTokenMs({ type: "assistant", time: { created: 2000, firstToken: 1000 } })).toBeUndefined()
  })

  test("a missing message is undefined", () => {
    expect(firstTokenMs(undefined)).toBeUndefined()
  })
})

describe("formatTtft", () => {
  test("one decimal, seconds", () => {
    expect(formatTtft(812)).toBe("0.8s")
    expect(formatTtft(1240)).toBe("1.2s")
    expect(formatTtft(0)).toBe("0.0s")
  })

  test("no value renders as a dash, keeping the row stable", () => {
    expect(formatTtft(undefined)).toBe("-")
  })
})

describe("withTtft", () => {
  test("adds without mutating the source", () => {
    const before = new Map([["a", 100]])
    const after = withTtft(before, "b", 200)
    expect([...after.entries()]).toEqual([
      ["a", 100],
      ["b", 200],
    ])
    expect([...before.keys()]).toEqual(["a"])
  })

  test("re-keys an existing session to the newest value", () => {
    const after = withTtft(new Map([["a", 100]]), "a", 250)
    expect(after.get("a")).toBe(250)
    expect([...after.keys()]).toEqual(["a"])
  })

  test("evicts the oldest past the cap", () => {
    let map = new Map<string, number>()
    for (const id of ["a", "b", "c"]) map = withTtft(map, id, 1, 2)
    expect([...map.keys()]).toEqual(["b", "c"])
  })
})
