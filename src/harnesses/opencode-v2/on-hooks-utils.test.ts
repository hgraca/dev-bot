// =============================================================================
// src/harnesses/opencode-v2/on-hooks-utils.test.ts
// Tool-name canonicalisation, V2 event payloads and file-write target
// extraction. These are the seams audit-01 FAIL-1/2/3 broke on:
//
//   FAIL-2  the guards matched only V1 tool names (`pty_spawn`), while the V2
//           plugin's tools reached the adapter as bare `spawn`/`write` — so
//           every PTY command bypassed the guards;
//   FAIL-3  `isPtyTool` had the same V1-only set, so the subagent guard never
//           fired;
//   FAIL-1  the adapter read `event.properties`, but a V2 event carries its
//           payload under `data`, so every event looked empty and no file hook
//           ran.
// =============================================================================

import { describe, expect, test } from "bun:test"
import { appendToToolResult, commandString, eventPayload, toolFileTargets, stampShellCall, stampShellIdentity } from "./on-hooks-utils"

describe("stampShellIdentity", () => {
  const CHILD = "ses_child01"
  const PARENT = "ses_parent01"

  test("leaves the command alone when the shell env already carries this session", () => {
    expect(stampShellIdentity("shell", "git status", CHILD, "scout", CHILD)).toBe("git status")
  })

  test("stamps the calling session when it is not the one the env was scoped to", () => {
    expect(stampShellIdentity("shell", "echo hi", CHILD, "scout", PARENT)).toBe(
      `export DEV_BOT_SESSION_ID='${CHILD}' DEV_BOT_AGENT_NAME='scout'; echo hi`,
    )
  })

  test("drops the inherited agent name when the calling agent is unknown", () => {
    const stamped = stampShellIdentity("shell", "echo hi", CHILD, undefined, PARENT)
    expect(stamped).toContain(`export DEV_BOT_SESSION_ID='${CHILD}'`)
    expect(stamped).toContain("unset DEV_BOT_AGENT_NAME")
    expect(stamped).not.toContain("DEV_BOT_AGENT_NAME='")
  })

  test("never touches a tool that is not a shell", () => {
    expect(stampShellIdentity("read", "x", CHILD, "scout", PARENT)).toBe("x")
    expect(stampShellIdentity("shell", "", CHILD, "scout", PARENT)).toBe("")
  })

  test("quotes a value instead of letting it break the command", () => {
    const stamped = stampShellIdentity("shell", "echo hi", "ses_ok", "it's", PARENT)
    expect(stamped).toContain(`DEV_BOT_AGENT_NAME='it'\\''s'`)
  })
})

describe("stampShellCall", () => {
  // The hook cannot be imported here (it needs the host runtime), so the
  // mutation it performs lives in this helper and is tested through the same
  // `input` object the hook passes.
  const CHILD = "ses_child01"
  const PARENT = "ses_parent01"

  test("rewrites the call's own input in place", () => {
    const input: { command?: string } = { command: "echo hi" }
    expect(stampShellCall("shell", input, CHILD, "scout", PARENT)).toBe(true)
    expect(input.command).toBe(
      `export DEV_BOT_SESSION_ID='${CHILD}' DEV_BOT_AGENT_NAME='scout'; echo hi`,
    )
  })

  test("reports false and leaves the input alone when nothing changes", () => {
    const input: { command?: string } = { command: "echo hi" }
    expect(stampShellCall("shell", input, CHILD, "scout", CHILD)).toBe(false)
    expect(input.command).toBe("echo hi")
  })

  test("is inert for a tool with no command, and for a missing input", () => {
    expect(stampShellCall("read", { path: "x" }, CHILD, "scout", PARENT)).toBe(false)
    expect(stampShellCall("shell", undefined, CHILD, "scout", PARENT)).toBe(false)
  })
})

describe("commandString", () => {
  test("returns the shell tool's command", () => {
    expect(commandString("shell", { command: "git status" })).toBe("git status")
    expect(commandString("bash", { command: "ls" })).toBe("ls")
  })
})

describe("eventPayload", () => {
  test("reads a V2 payload from `data`", () => {
    expect(eventPayload({ type: "file.edited", data: { file: "/a.md" } })).toEqual({ file: "/a.md" })
  })

  test("still reads a V1 payload from `properties`", () => {
    expect(eventPayload({ type: "file.edited", properties: { file: "/a.md" } })).toEqual({ file: "/a.md" })
  })

  test("prefers `data` when a host sends both", () => {
    expect(eventPayload({ data: { file: "/new" }, properties: { file: "/old" } })).toEqual({ file: "/new" })
  })

  test("is empty for a shapeless event", () => {
    expect(eventPayload({ type: "session.idle" })).toEqual({})
    expect(eventPayload(null)).toEqual({})
  })
})

describe("toolFileTargets", () => {
  test("reads the V2 `path` field", () => {
    expect(toolFileTargets("edit", { path: "src/a.ts" })).toEqual(["src/a.ts"])
    expect(toolFileTargets("write", { path: "docs/a.md", content: "x" })).toEqual(["docs/a.md"])
  })

  test("reads the V1 `filePath` field", () => {
    expect(toolFileTargets("edit", { filePath: "src/a.ts" })).toEqual(["src/a.ts"])
  })

  test("collects every file a patch touches", () => {
    const patchText = [
      "*** Begin Patch",
      "*** Update File: src/a.ts",
      "@@",
      "-a",
      "+b",
      "*** Add File: src/b.ts",
      "+new",
      "*** Delete File: src/c.ts",
      "*** End Patch",
    ].join("\n")
    expect(toolFileTargets("patch", { patchText })).toEqual(["src/a.ts", "src/b.ts", "src/c.ts"])
    // The adapter advertises `apply_patch` too: the same payload must parse, or
    // its edits are never scheduled for the file hooks.
    expect(toolFileTargets("apply_patch", { patchText })).toEqual(["src/a.ts", "src/b.ts", "src/c.ts"])
  })

  test("is empty for a tool that writes no file", () => {
    expect(toolFileTargets("shell", { command: "echo hi > a.md" })).toEqual([])
    expect(toolFileTargets("spawn", { command: "touch a.md" })).toEqual([])
    expect(toolFileTargets("edit", {})).toEqual([])
  })
})

// ── surface: "tool-result" ───────────────────────────────────────────────────
// A hook that declares `surface` has its stdout folded into the tool result of
// the edit that triggered it, so the finding reaches the model in the same turn
// instead of only reaching a log file. v2's result is Tool.Result: `content` is
// a string or content parts, never v1's flat `output` string.

describe("appendToToolResult", () => {
  test("appends a text part to a Tool.Result with content parts", () => {
    const result: any = { content: [{ type: "text", text: "edited" }], metadata: {} }
    expect(appendToToolResult(result, "line 4: [gradient-text]")).toBe(true)
    expect(result.content).toEqual([
      { type: "text", text: "edited" },
      { type: "text", text: "line 4: [gradient-text]" },
    ])
  })

  test("appends to a string content body", () => {
    const result: any = { content: "edited" }
    expect(appendToToolResult(result, "finding")).toBe(true)
    expect(result.content).toBe("edited\n\nfinding")
  })

  test("still handles a v1-shaped result (flat output string)", () => {
    const result: any = { output: "edited" }
    expect(appendToToolResult(result, "finding")).toBe(true)
    expect(result.output).toBe("edited\n\nfinding")
  })

  test("returns false on a shape with no text field", () => {
    expect(appendToToolResult({ metadata: {} }, "finding")).toBe(false)
    expect(appendToToolResult(undefined, "finding")).toBe(false)
  })

  test("empty or whitespace findings are a no-op", () => {
    const result: any = { content: "edited" }
    expect(appendToToolResult(result, "\n  ")).toBe(false)
    expect(result.content).toBe("edited")
  })
})
