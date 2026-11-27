// Unit tests for the idle pass's pure decisions: which message ended the turn,
// the parts the validator reads, and the marker that gets published.

import { describe, test, expect } from "bun:test"
import {
  isCheckedStatus,
  lastAssistantMessage,
  markerForReport,
  markerFromOutput,
  textParts,
  waitEvidenceParts,
} from "./idle"

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

describe("waitEvidenceParts", () => {
  test("flattens a tool part's status and background flag", () => {
    const message = {
      parts: [
        { type: "text", text: "hi" },
        { type: "tool", tool: "bash", state: { status: "completed", input: { background: true } } },
      ],
    }
    expect(waitEvidenceParts(message)).toEqual([
      { type: "tool", tool: "bash", status: "completed", background: true },
    ])
  })

  test("reads a string state, as some harness shapes report it", () => {
    expect(waitEvidenceParts({ parts: [{ type: "tool", tool: "pty_spawn", state: "completed" }] })).toEqual([
      { type: "tool", tool: "pty_spawn", status: "completed", background: false },
    ])
  })

  test("treats a background string as backgrounded", () => {
    const parts = waitEvidenceParts({
      parts: [{ type: "tool", tool: "shell", state: { status: "completed", input: { background: "true" } } }],
    })
    expect(parts[0].background).toBe(true)
  })

  test("keeps a failed part visible so the validator can reject it", () => {
    const parts = waitEvidenceParts({ parts: [{ type: "tool", tool: "pty_spawn", state: { status: "error" } }] })
    expect(parts).toEqual([{ type: "tool", tool: "pty_spawn", status: "error", background: false }])
  })

  test("returns nothing for a text-only message", () => {
    expect(waitEvidenceParts({ parts: [{ type: "text", text: "x" }] })).toEqual([])
    expect(waitEvidenceParts(undefined)).toEqual([])
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

describe("markerFromOutput", () => {
  test("reads the terminal marker the validator named", () => {
    expect(markerFromOutput("[agent-communication] OK — terminal marker found: PARTIAL")).toBe("PARTIAL")
  })

  test("reads a marker whose name carries an underscore", () => {
    expect(markerFromOutput("OK — terminal marker found: NEEDS_INPUT")).toBe("NEEDS_INPUT")
  })

  test("returns nothing when the pass line names no terminal marker", () => {
    expect(markerFromOutput("OK — terminal marker found")).toBeUndefined()
  })

  test("returns nothing for a finding or empty output", () => {
    expect(markerFromOutput('Missing terminal marker. Last line: "hello"')).toBeUndefined()
    expect(markerFromOutput("")).toBeUndefined()
  })
})

describe("markerForReport", () => {
  test("a pass publishes the marker it named", () => {
    expect(markerForReport(0, "OK — terminal marker found: FINISHED")).toBe("FINISHED")
  })

  test("a pass with no terminal marker publishes none, so the token clears", () => {
    expect(markerForReport(0, "OK — terminal marker found")).toBeUndefined()
  })

  test("a finding clears rather than naming the message's marker", () => {
    expect(markerForReport(1, "OK — terminal marker found: BLOCKED")).toBeUndefined()
  })

  test("a failed invocation publishes nothing at all", () => {
    expect(markerForReport(2, "")).toBeUndefined()
    expect(markerForReport(null, "")).toBeUndefined()
  })
})
