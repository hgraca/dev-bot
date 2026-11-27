// Shape tests for the v2 adapter, plus one end-to-end pass over a fake v2
// context: the v2 entries must reach the idle pass as messages it understands.

import { describe, test, expect, beforeEach, afterEach } from "bun:test"
import { existsSync } from "node:fs"
import { join } from "node:path"
import { DEV_BOT_ROOT, forEachIdle, idleEvent, messageFromEntry, responseEntries, v2Client } from "./lib"
import { makeOnSessionIdleValidate } from "../../../../agentic/agent-communication/hooks/opencode/on-session-idle-validate"

const HERDR_KEYS = ["HERDR_ENV", "HERDR_PANE_ID", "HERDR_BIN_PATH"] as const
const saved: Array<[string, string | undefined]> = []
const silent = { debug() {}, info() {}, notice() {}, warn() {}, error() {}, fatal() {} }

function fakeCtx(entries: unknown[], session: unknown) {
  const calls: string[] = []
  return {
    calls,
    // A client response wraps its entries in `data`.
    ctx: {
      session: {
        context: async ({ sessionID }: any) => {
          calls.push(sessionID)
          return { data: entries }
        },
        get: async () => session,
      },
    },
  }
}

async function idleOver(entries: unknown[], session: unknown) {
  const { ctx } = fakeCtx(entries, session)
  const plans: any[] = []
  const plugin: any = await makeOnSessionIdleValidate({
    validate: async () => ({ status: 0, stdout: "OK — terminal marker found: FINISHED", stderr: "" }),
    writeMessage: () => ({ file: "/tmp/devbot-v2-message.json", cleanup() {} }),
    report: async (plan) => {
      plans.push(plan)
      return true
    },
    log: silent,
  })({ directory: "/tmp/opencode", worktree: "/tmp/opencode", client: v2Client(ctx) } as any)
  await plugin.event({ event: { type: "session.idle", properties: { sessionID: "s1" } } })
  return plans
}

beforeEach(() => {
  saved.length = 0
  for (const key of HERDR_KEYS) saved.push([key, process.env[key]])
  process.env.HERDR_ENV = "1"
  process.env.HERDR_PANE_ID = "w1:p1"
  process.env.HERDR_BIN_PATH = "/opt/herdr"
})

afterEach(() => {
  for (const [key, value] of saved) {
    if (value === undefined) delete process.env[key]
    else process.env[key] = value
  }
})

describe("idleEvent", () => {
  test("reads the session id from a v2 event's data", () => {
    expect(idleEvent({ type: "session.idle", data: { sessionID: "s1" } }).properties.sessionID).toBe("s1")
  })

  test("falls back to the info id a v2 payload may carry", () => {
    expect(idleEvent({ type: "session.idle", data: { info: { id: "s2" } } }).properties.sessionID).toBe("s2")
  })

  test("still accepts an already-normalised event", () => {
    expect(idleEvent({ type: "session.idle", properties: { sessionID: "s3" } }).properties.sessionID).toBe("s3")
  })
})

describe("forEachIdle", () => {
  test("hands the idle pass an event whose payload it can read", async () => {
    const seen: string[] = []
    const ctx = {
      event: {
        subscribe: async function* () {
          yield { type: "session.updated", data: { sessionID: "s8" } }
          yield { type: "session.idle", data: { sessionID: "s9" } }
        },
      },
    }
    await forEachIdle(ctx, async (event) => {
      seen.push(event.properties.sessionID)
    })
    expect(seen).toEqual(["s9"])
  })
})

describe("DEV_BOT_ROOT", () => {
  test("points at the repository root, not src/", () => {
    expect(existsSync(join(DEV_BOT_ROOT, "src", "agentic"))).toBe(true)
  })
})

describe("responseEntries", () => {
  test("unwraps the client response's data array", () => {
    expect(responseEntries({ data: [1, 2] })).toEqual([1, 2])
  })

  test("accepts a bare array from an older host", () => {
    expect(responseEntries([3])).toEqual([3])
  })

  test("returns nothing for a response with no entries", () => {
    expect(responseEntries(undefined)).toEqual([])
    expect(responseEntries({ data: null })).toEqual([])
  })
})

describe("messageFromEntry", () => {
  test("passes a message-shaped entry through unchanged", () => {
    const entry = { info: { role: "assistant", id: "m1" }, parts: [{ type: "text", text: "x" }] }
    expect(messageFromEntry(entry)).toBe(entry)
  })

  test("turns a v2 context entry into the message the validator reads", () => {
    expect(
      messageFromEntry({
        id: "m1",
        type: "assistant",
        content: [{ type: "text", text: "hi" }],
      }),
    ).toEqual({ info: { role: "assistant", id: "m1", parentID: undefined }, parts: [{ type: "text", text: "hi" }] })
  })

  test("carries no parts when the entry has no content", () => {
    expect(messageFromEntry({ id: "m1", type: "user" }).parts).toEqual([])
  })
})

describe("v2Client", () => {
  test("reads the session's context as messages", async () => {
    const { ctx, calls } = fakeCtx([{ id: "m1", type: "assistant", content: [] }], { id: "s1" })
    const data = (await v2Client(ctx).session.messages({ path: { id: "s1" } })).data
    expect(calls).toEqual(["s1"])
    expect(data[0].info.role).toBe("assistant")
  })

  test("reads the session itself, parentID included", async () => {
    const { ctx } = fakeCtx([], { id: "s1", parentID: "root" })
    const data = (await v2Client(ctx).session.get({ path: { id: "s1" } })).data
    expect(data.parentID).toBe("root")
  })
})

describe("the idle pass over a v2 context", () => {
  test("publishes the marker of the assistant entry that ended the turn", async () => {
    const plans = await idleOver(
      [
        { id: "u1", type: "user", content: [{ type: "text", text: "do it" }] },
        {
          id: "m1",
          type: "assistant",
          content: [
            { type: "text", text: "Done." },
            { type: "tool", name: "shell", state: { status: "completed", input: {} } },
            { type: "text", text: "[FINISHED]" },
          ],
        },
      ],
      { id: "s1" },
    )
    expect(plans).toHaveLength(1)
    expect(plans[0].args).toContain("devbot=FINISHED")
  })

  test("publishes nothing when the last entry is not an assistant turn", async () => {
    const plans = await idleOver([{ id: "u1", type: "user", content: [{ type: "text", text: "hi" }] }], {
      id: "s1",
    })
    expect(plans).toHaveLength(0)
  })

  test("publishes for a raw v2 event, which carries data rather than properties", async () => {
    const { ctx } = fakeCtx(
      [{ id: "m1", type: "assistant", content: [{ type: "text", text: "[FINISHED]" }] }],
      { id: "s1" },
    )
    const plans: any[] = []
    const plugin: any = await makeOnSessionIdleValidate({
      validate: async () => ({ status: 0, stdout: "OK — terminal marker found: FINISHED", stderr: "" }),
      writeMessage: () => ({ file: "/tmp/devbot-v2-message.json", cleanup() {} }),
      report: async (plan) => {
        plans.push(plan)
        return true
      },
      log: silent,
    })({ directory: "/tmp/opencode", worktree: "/tmp/opencode", client: v2Client(ctx) } as any)

    await plugin.event({ event: idleEvent({ type: "session.idle", data: { sessionID: "s1" } }) })
    expect(plans).toHaveLength(1)
  })

  test("a subagent session never publishes", async () => {
    const plans = await idleOver(
      [{ id: "m1", type: "assistant", content: [{ type: "text", text: "[FINISHED]" }] }],
      { id: "s1", parentID: "root" },
    )
    expect(plans).toHaveLength(0)
  })
})
