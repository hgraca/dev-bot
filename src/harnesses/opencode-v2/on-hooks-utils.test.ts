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
import { commandString, eventPayload, toolFileTargets } from "./on-hooks-utils"

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
  })

  test("is empty for a tool that writes no file", () => {
    expect(toolFileTargets("shell", { command: "echo hi > a.md" })).toEqual([])
    expect(toolFileTargets("spawn", { command: "touch a.md" })).toEqual([])
    expect(toolFileTargets("edit", {})).toEqual([])
  })
})

