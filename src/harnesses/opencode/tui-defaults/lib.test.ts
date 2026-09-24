// =============================================================================
// src/harnesses/opencode/tui-defaults/lib.test.ts
// Tests for the tool-details default plugin.
//
// The one rule this guards is the whole point of the plugin: dev-bot's default
// (details hidden) applies ONLY to a user who has never configured one. A value
// already in kv — whatever it holds — is an explicit choice and must survive,
// or the plugin would fight the very toggle it exists to replace.
// =============================================================================

import { describe, expect, test } from "bun:test"
import { seedToolDetailsDefault, TOOL_DETAILS_KEY, type Kv } from "./lib"
import plugin from "./index"

/** An in-memory stand-in for opencode's kv store, recording every write. */
function fakeKv(initial: Record<string, unknown> = {}) {
  const store = new Map(Object.entries(initial))
  const writes: Array<{ key: string; value: unknown }> = []
  const kv: Kv = {
    get: (key) => store.get(key),
    set: (key, value) => {
      writes.push({ key, value })
      store.set(key, value)
    },
  }
  return { kv, writes, store }
}

describe("seedToolDetailsDefault", () => {
  test("seeds hidden when the user has never configured it", () => {
    const { kv, writes } = fakeKv()
    expect(seedToolDetailsDefault(kv)).toBe(true)
    expect(writes).toEqual([{ key: TOOL_DETAILS_KEY, value: false }])
  })

  test("leaves an explicit 'show' alone", () => {
    // Someone who turned tool details back on made a choice; re-hiding them on
    // the next start would be the plugin overriding the user.
    const { kv, writes } = fakeKv({ [TOOL_DETAILS_KEY]: true })
    expect(seedToolDetailsDefault(kv)).toBe(false)
    expect(writes).toEqual([])
  })

  test("leaves an explicit 'hide' alone", () => {
    // Already hidden — a no-op, not a rewrite. `false` is the seeded value, so a
    // truthiness check would re-write it on every single start.
    const { kv, writes } = fakeKv({ [TOOL_DETAILS_KEY]: false })
    expect(seedToolDetailsDefault(kv)).toBe(false)
    expect(writes).toEqual([])
  })

  test("writes nothing but its own key", () => {
    const { kv, writes } = fakeKv({ unrelated: 1 })
    seedToolDetailsDefault(kv)
    expect(writes.map((w) => w.key)).toEqual([TOOL_DETAILS_KEY])
  })
})

describe("the plugin entry point", () => {
  test("seeds the default through the kv it is handed", async () => {
    const { kv, writes } = fakeKv()
    await plugin.tui({ kv })
    expect(writes).toEqual([{ key: TOOL_DETAILS_KEY, value: false }])
  })

  test("does not override an existing choice on load", async () => {
    const { kv, writes } = fakeKv({ [TOOL_DETAILS_KEY]: true })
    await plugin.tui({ kv })
    expect(writes).toEqual([])
  })
})
