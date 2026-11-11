// Unit tests for the agent-communication session.idle hook. The hook is
// log-only, so the guards that matter are: which message is validated, how its
// text is extracted, and that a failed invocation stays retryable rather than
// being marked checked.

import { describe, test, expect } from "bun:test"
import { isCheckedStatus, lastAssistantMessage, textParts } from "./on-session-idle-validate"

function message(role: string, parts: unknown[] = []): Record<string, unknown> {
  return { info: { role, id: `${role}-id` }, parts }
}

describe("lastAssistantMessage", () => {
  test("returns the last assistant message among mixed roles", () => {
    const messages = [message("user"), message("assistant"), message("user"), message("assistant")]
    expect(lastAssistantMessage(messages)).toBe(messages[3])
  })

  test("skips a trailing non-assistant message", () => {
    const messages = [message("assistant"), message("user")]
    expect(lastAssistantMessage(messages)).toBe(messages[0])
  })

  test("returns undefined when there is no assistant message", () => {
    expect(lastAssistantMessage([message("user")])).toBeUndefined()
  })

  test("returns undefined for non-array input", () => {
    expect(lastAssistantMessage(undefined)).toBeUndefined()
  })
})

describe("textParts", () => {
  test("keeps text parts and drops the rest", () => {
    expect(
      textParts({ parts: [{ type: "tool", state: "completed" }, { type: "text", text: "hi" }] }),
    ).toEqual([{ type: "text", text: "hi" }])
  })

  test("coerces missing text to an empty string", () => {
    expect(textParts({ parts: [{ type: "text" }] })).toEqual([{ type: "text", text: "" }])
  })

  test("returns an empty list when there are no parts", () => {
    expect(textParts({})).toEqual([])
  })
})

describe("isCheckedStatus", () => {
  test("a pass (0) or a finding (1) marks the message checked", () => {
    expect(isCheckedStatus(0)).toBe(true)
    expect(isCheckedStatus(1)).toBe(true)
  })

  test("a failed invocation (2 or null) stays retryable", () => {
    expect(isCheckedStatus(2)).toBe(false)
    expect(isCheckedStatus(null)).toBe(false)
    expect(isCheckedStatus(undefined)).toBe(false)
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
