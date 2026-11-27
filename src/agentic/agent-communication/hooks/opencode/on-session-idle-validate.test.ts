// Behaviour tests for the session.idle hook: the manifest wiring, and the
// decision to publish a marker to herdr — driven through the factory with a
// fake client, validator and reporter.

import { describe, test, expect, beforeEach, afterEach } from "bun:test"
import { makeOnSessionIdleValidate } from "./on-session-idle-validate"
import type { HerdrPlan } from "../../lib/herdr-report"
import type { ValidatorResult } from "../../lib/validator"

const HERDR_KEYS = ["HERDR_ENV", "HERDR_PANE_ID", "HERDR_BIN_PATH"] as const
const saved: Array<[string, string | undefined]> = []

const silent = { debug() {}, info() {}, notice() {}, warn() {}, error() {}, fatal() {} }

function assistant(text: string) {
  return { info: { role: "assistant", id: "m1" }, parts: [{ type: "text", text }] }
}

function fakeClient(messages: unknown[], sessions: Record<string, unknown> = {}) {
  return {
    session: {
      messages: async () => ({ data: messages }),
      get: async ({ path }: any) => ({ data: sessions[path.id] }),
    },
  }
}

interface RunOptions {
  result: ValidatorResult
  messages?: unknown[]
  sessions?: Record<string, unknown>
  client?: unknown
}

async function idle(options: RunOptions) {
  const plans: HerdrPlan[] = []
  let validations = 0
  const plugin = await makeOnSessionIdleValidate({
    validate: async () => {
      validations += 1
      return options.result
    },
    writeMessage: () => ({ file: "/tmp/devbot-test-message.json", cleanup() {} }),
    report: async (plan) => {
      plans.push(plan)
      return true
    },
    log: silent,
  })({
    directory: "/tmp/opencode",
    worktree: "/tmp/opencode",
    client: options.client ?? fakeClient(options.messages ?? [assistant("Done.\n\n[PARTIAL]")], options.sessions),
  } as any)

  await (plugin as any).event({ event: { type: "session.idle", properties: { sessionID: "s1" } } })
  return { plans, validations }
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

describe("publishing the marker", () => {
  test("a pass publishes the marker the validator named", async () => {
    const { plans } = await idle({
      result: { status: 0, stdout: "OK — terminal marker found: PARTIAL", stderr: "" },
    })
    expect(plans).toHaveLength(1)
    expect(plans[0].args).toContain("devbot=PARTIAL")
    expect(plans[0].args.slice(0, 3)).toEqual(["pane", "report-metadata", "w1:p1"])
  })

  test("a pass with no terminal marker clears the token", async () => {
    const { plans } = await idle({
      result: { status: 0, stdout: "OK — terminal marker found", stderr: "" },
    })
    expect(plans).toHaveLength(1)
    expect(plans[0].args).toContain("devbot=")
  })

  test("a finding clears the token", async () => {
    const { plans } = await idle({
      result: { status: 1, stdout: "", stderr: "Missing terminal marker." },
    })
    expect(plans).toHaveLength(1)
    expect(plans[0].args).toContain("devbot=")
  })

  test("a failed invocation publishes nothing and stays retryable", async () => {
    const { plans, validations } = await idle({
      result: { status: 2, stdout: "", stderr: "jq is required" },
    })
    expect(plans).toHaveLength(0)
    expect(validations).toBe(1)
  })

  test("a subagent session never publishes: the pane's turn has not ended", async () => {
    const { plans } = await idle({
      result: { status: 0, stdout: "OK — terminal marker found: FINISHED", stderr: "" },
      sessions: { s1: { id: "s1", parentID: "root" } },
    })
    expect(plans).toHaveLength(0)
  })

  test("a root session publishes", async () => {
    const { plans } = await idle({
      result: { status: 0, stdout: "OK — terminal marker found: FINISHED", stderr: "" },
      sessions: { s1: { id: "s1" } },
    })
    expect(plans).toHaveLength(1)
    expect(plans[0].args).toContain("devbot=FINISHED")
  })

  test("outside a herdr pane nothing is published", async () => {
    delete process.env.HERDR_ENV
    const { plans, validations } = await idle({
      result: { status: 0, stdout: "OK — terminal marker found: FINISHED", stderr: "" },
    })
    expect(plans).toHaveLength(0)
    expect(validations).toBe(1)
  })

  test("one turn validates and publishes once, even on a repeated idle", async () => {
    const plans: HerdrPlan[] = []
    let validations = 0
    const plugin = await makeOnSessionIdleValidate({
      validate: async () => {
        validations += 1
        return { status: 0, stdout: "OK — terminal marker found: IDLE", stderr: "" }
      },
      writeMessage: () => ({ file: "/tmp/devbot-test-message.json", cleanup() {} }),
      report: async (plan) => {
        plans.push(plan)
        return true
      },
      log: silent,
    })({
      directory: "/tmp/opencode",
      worktree: "/tmp/opencode",
      client: fakeClient([assistant("Done.\n\n[FINISHED]")]),
    } as any)

    const event = { event: { type: "session.idle", properties: { sessionID: "s1" } } }
    await (plugin as any).event(event)
    await (plugin as any).event(event)

    expect(validations).toBe(1)
    expect(plans).toHaveLength(1)
  })
})

describe("manifest wiring", () => {
  test("registers the plugin for session.idle", async () => {
    const raw = await Bun.file(import.meta.dir + "/../../hooks.json").text()
    const manifest = JSON.parse(raw)
    const hook = (manifest.hooks ?? []).find((h: any) => h.event === "session.idle")
    expect(hook).toBeDefined()
    expect(hook.plugin).toContain("on-session-idle-validate.ts")
  })
})
