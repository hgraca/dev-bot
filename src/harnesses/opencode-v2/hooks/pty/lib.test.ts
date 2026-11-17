// =============================================================================
// src/harnesses/opencode-v2/hooks/pty/lib.test.ts
// The PTY extension's shared logic: the published info shape (including the
// `parentSessionId` PR #91 adds), the sidebar row and header text, the panel's
// detail block, and the read pagination.
// =============================================================================

import { describe, expect, test } from "bun:test"
import {
  CONTROL_KEYS,
  clearActionLabel,
  dropSelection,
  filterByFamily,
  filterByParent,
  finishedSessions,
  formatDetail,
  formatDuration,
  headerLabel,
  isFinished,
  lineInput,
  needsConfirm,
  pageLines,
  parentSessionIdOf,
  selectedSession,
  selectSession,
  rowLabel,
  rowTone,
  runDurationMs,
  sessionInfo,
  statusOf,
  tailLines,
  type PtyRecord,
} from "./lib"

const CREATED = Date.parse("2026-11-17T10:00:00.000Z")

const record = (over: Partial<PtyRecord> = {}): PtyRecord => ({
  id: "pty_abc12345",
  title: "npm run dev",
  command: "npm run dev",
  workdir: "/project",
  pid: 4242,
  parentSessionId: "ses_parent",
  createdAt: CREATED,
  exitAt: null,
  exitCode: null,
  killed: false,
  lineCount: 3,
  ...over,
})

describe("sessionInfo", () => {
  test("publishes the spawning agent session, so a client can filter by it", () => {
    // The field shekohex/opencode-pty#91 adds; without it the sidebar cannot
    // tell whose PTY a row is.
    expect(sessionInfo(record()).parentSessionId).toBe("ses_parent")
  })

  test("timestamps are ISO strings, and an unset exit time stays null", () => {
    const running = sessionInfo(record())
    expect(running.createdAt).toBe("2026-11-17T10:00:00.000Z")
    expect(running.exitAt).toBeNull()

    const exited = sessionInfo(record({ exitAt: CREATED + 1500, exitCode: 0 }))
    expect(exited.exitAt).toBe("2026-11-17T10:00:01.500Z")
  })

  test("carries every field the sidebar and panel read", () => {
    expect(sessionInfo(record())).toEqual({
      id: "pty_abc12345",
      title: "npm run dev",
      command: "npm run dev",
      workdir: "/project",
      status: "running",
      pid: 4242,
      exitCode: null,
      exitAt: null,
      createdAt: "2026-11-17T10:00:00.000Z",
      lineCount: 3,
      parentSessionId: "ses_parent",
    })
  })
})

describe("statusOf", () => {
  test("running until the exit callback stamps a time", () => {
    expect(statusOf({ exitAt: null, killed: false })).toBe("running")
  })

  test("exited when the child ended on its own", () => {
    expect(statusOf({ exitAt: CREATED + 10, killed: false })).toBe("exited")
  })

  test("killed outranks the exit code: a stopped session did not fail", () => {
    expect(statusOf({ exitAt: CREATED + 10, killed: true })).toBe("killed")
  })
})

describe("filterByParent", () => {
  const one = sessionInfo(record({ id: "pty_1", parentSessionId: "ses_a" }))
  const two = sessionInfo(record({ id: "pty_2", parentSessionId: "ses_b" }))

  test("keeps only the sessions this agent session spawned", () => {
    expect(filterByParent([one, two], "ses_a").map((s) => s.id)).toEqual(["pty_1"])
  })

  test("an empty parent means every session, which is what the RPC does", () => {
    expect(filterByParent([one, two], "")).toHaveLength(2)
  })

  test("a session nobody owns yet is not shown under a parent filter", () => {
    expect(filterByParent([sessionInfo(record({ parentSessionId: "" }))], "ses_a")).toEqual([])
  })
})

describe("filterByFamily", () => {
  const root = sessionInfo(record({ id: "pty_root", parentSessionId: "ses_root" }))
  const child = sessionInfo(record({ id: "pty_child", parentSessionId: "ses_child" }))
  const stranger = sessionInfo(record({ id: "pty_other", parentSessionId: "ses_other" }))

  test("a subagent's PTY belongs to the session in view", () => {
    // The common case: the agent delegates, the subagent spawns the dev server.
    const mine = filterByFamily([root, child, stranger], ["ses_root", "ses_child"])
    expect(mine.map((s) => s.id)).toEqual(["pty_root", "pty_child"])
  })

  test("a session with no subagents still sees its own PTYs", () => {
    expect(filterByFamily([root, stranger], ["ses_root"]).map((s) => s.id)).toEqual(["pty_root"])
  })

  test("an empty family matches nothing, not everything", () => {
    expect(filterByFamily([root, child], [])).toEqual([])
  })
})

describe("parentSessionIdOf", () => {
  test("reads the spawning session from the tool context", () => {
    expect(parentSessionIdOf({ sessionID: "ses_parent" })).toBe("ses_parent")
  })

  test("a context without one yields an empty owner, never 'undefined'", () => {
    expect(parentSessionIdOf({})).toBe("")
    expect(parentSessionIdOf(undefined)).toBe("")
    expect(parentSessionIdOf(null)).toBe("")
    expect(parentSessionIdOf({ sessionID: 42 })).toBe("")
  })
})

describe("opening a row", () => {
  test("the clicked row is the session the panel shows", () => {
    // The hand-off the sidebar click performs: pick a row for this viewer.
    const after = selectSession({}, "ses_viewer", "pty_a")
    expect(selectedSession(after, "ses_viewer")).toBe("pty_a")
  })

  test("each agent session remembers its own row", () => {
    const one = selectSession({}, "ses_one", "pty_a")
    const two = selectSession(one, "ses_two", "pty_b")
    expect(selectedSession(two, "ses_one")).toBe("pty_a")
    expect(selectedSession(two, "ses_two")).toBe("pty_b")
  })

  test("opening a second row replaces the first, it does not stack", () => {
    const after = selectSession(selectSession({}, "ses_viewer", "pty_a"), "ses_viewer", "pty_b")
    expect(selectedSession(after, "ses_viewer")).toBe("pty_b")
  })

  test("a panel with no row picked shows nothing, not another session's row", () => {
    const picked = selectSession({}, "ses_other", "pty_a")
    expect(selectedSession(picked, "ses_viewer")).toBe("")
    expect(selectedSession(picked, undefined)).toBe("")
  })
})

describe("rowLabel", () => {
  test("running sessions show their line count", () => {
    expect(rowLabel(sessionInfo(record()))).toBe("npm run dev  3L")
  })

  test("a non-zero exit shows the code", () => {
    expect(rowLabel(sessionInfo(record({ exitAt: CREATED + 1, exitCode: 2 })))).toBe(
      "npm run dev  exit 2",
    )
  })

  test("a killed session shows the status word, not a phantom code", () => {
    expect(rowLabel(sessionInfo(record({ exitAt: CREATED + 1, killed: true })))).toBe(
      "npm run dev  killed",
    )
  })

  test("the title column is capped, and the command stands in for a missing title", () => {
    const long = sessionInfo(record({ title: "a".repeat(40) }))
    expect(rowLabel(long).split("  ")[0]).toHaveLength(24)
    expect(rowLabel(sessionInfo(record({ title: "" })))).toStartWith("npm run dev")
  })
})

describe("rowTone", () => {
  test("live is success, a failing exit is an error, anything else is muted", () => {
    expect(rowTone(sessionInfo(record()))).toBe("success")
    expect(rowTone(sessionInfo(record({ exitAt: CREATED, exitCode: 1 })))).toBe("error")
    expect(rowTone(sessionInfo(record({ exitAt: CREATED, exitCode: 0 })))).toBe("muted")
  })
})

describe("sending input", () => {
  test("a submitted line ends with a carriage return, which is Enter", () => {
    // A PTY in canonical mode reads CR as Enter; a bare LF leaves some
    // prompts waiting for the rest of the line.
    expect(lineInput("hunter2")).toBe("hunter2\r")
  })

  test("an empty submit still sends Enter, not nothing", () => {
    expect(lineInput("")).toBe("\r")
  })

  test("the control keys carry the bytes a terminal would send", () => {
    const byLabel = (label: string) => CONTROL_KEYS.find((key) => key.label.startsWith(label))?.data
    expect(byLabel("Escape")).toBe("\u001b")
    expect(byLabel("Tab")).toBe("\t")
    expect(byLabel("Ctrl+C")).toBe("\u0003")
    expect(byLabel("Ctrl+D")).toBe("\u0004")
    expect(byLabel("Arrow up")).toBe("\u001b[A")
  })

  test("every offered key is sendable", () => {
    expect(CONTROL_KEYS.length).toBeGreaterThan(0)
    for (const key of CONTROL_KEYS) {
      expect(key.label.length).toBeGreaterThan(0)
      expect(key.data.length).toBeGreaterThan(0)
    }
  })
})

describe("dismissal", () => {
  const running = sessionInfo(record({ id: "pty_run", parentSessionId: "ses_a" }))
  const exited = sessionInfo(
    record({ id: "pty_done", parentSessionId: "ses_a", exitAt: CREATED + 10, exitCode: 0 }),
  )
  const killed = sessionInfo(
    record({ id: "pty_stopped", parentSessionId: "ses_a", exitAt: CREATED + 10, killed: true }),
  )

  test("only a running session counts as live", () => {
    expect(isFinished(running)).toBe(false)
    expect(isFinished(exited)).toBe(true)
    expect(isFinished(killed)).toBe(true)
  })

  test("removing a live process asks first; a record goes at once", () => {
    expect(needsConfirm(running)).toBe(true)
    expect(needsConfirm(exited)).toBe(false)
    expect(needsConfirm(killed)).toBe(false)
  })

  test("clear-finished targets every stopped session and no live one", () => {
    // Dropping a live row here would kill a process the user never pointed at.
    expect(finishedSessions([running, exited, killed]).map((s) => s.id)).toEqual([
      "pty_done",
      "pty_stopped",
    ])
  })

  test("the clear action is offered only when something can be cleared", () => {
    expect(clearActionLabel([running])).toBeNull()
    expect(clearActionLabel([])).toBeNull()
    expect(clearActionLabel([running, exited])).toBe("(clear finished)")
  })
})

describe("dropSelection", () => {
  test("removing the row the panel shows clears that viewer's selection", () => {
    const picked = selectSession({}, "ses_viewer", "pty_a")
    expect(dropSelection(picked, "ses_viewer", "pty_a")).toEqual({})
  })

  test("removing another row leaves the open panel alone", () => {
    const picked = selectSession({}, "ses_viewer", "pty_a")
    expect(dropSelection(picked, "ses_viewer", "pty_b")).toEqual(picked)
  })

  test("another session's selection is never touched", () => {
    const one = selectSession({}, "ses_one", "pty_a")
    const two = selectSession(one, "ses_two", "pty_b")
    expect(dropSelection(two, "ses_two", "pty_b")).toEqual({ "ses_one": "pty_a" })
  })
})

describe("headerLabel", () => {
  test("counts the sessions, naming how many are still live", () => {
    expect(headerLabel({ count: 0, running: 0 })).toBe("PTY")
    expect(headerLabel({ count: 2, running: 2 })).toBe("PTY 2 running")
    expect(headerLabel({ count: 2, running: 1 })).toBe("PTY 2")
  })
})

describe("formatDetail", () => {
  test("two lines: the numbers, then the command and its workdir", () => {
    const lines = formatDetail(sessionInfo(record())).split("\n")
    expect(lines).toHaveLength(2)
    expect(lines[0]).toBe("pty_abc12345  running  pid 4242  3 lines")
    expect(lines[1]).toBe("npm run dev  ·  /project")
  })
})

describe("formatDuration", () => {
  test("seconds below a minute, then the leading unit", () => {
    expect(formatDuration(0)).toBe("0s")
    expect(formatDuration(9_000)).toBe("9s")
    expect(formatDuration(65_000)).toBe("1m 05s")
    expect(formatDuration(3_600_000 * 2 + 420_000)).toBe("2h 07m")
  })

  test("a nonsense duration reads as zero rather than NaN", () => {
    expect(formatDuration(Number.NaN)).toBe("0s")
    expect(formatDuration(-5)).toBe("0s")
  })
})

describe("runDurationMs", () => {
  test("a running session counts up to now", () => {
    expect(runDurationMs(sessionInfo(record()), CREATED + 5_000)).toBe(5_000)
  })

  test("an exited one stops at its exit time", () => {
    const info = sessionInfo(record({ exitAt: CREATED + 2_000, exitCode: 0 }))
    expect(runDurationMs(info, CREATED + 60_000)).toBe(2_000)
  })

  test("an unparseable start time yields null, never a wrong number", () => {
    expect(runDurationMs({ createdAt: "not-a-date", exitAt: null }, CREATED)).toBeNull()
  })
})

describe("tailLines", () => {
  test("keeps the newest lines and marks that output was cut", () => {
    expect(tailLines(["1", "2", "3", "4"], 2)).toEqual(["…", "3", "4"])
  })

  test("a buffer that fits is returned untouched", () => {
    expect(tailLines(["1", "2"], 5)).toEqual(["1", "2"])
  })
})

describe("pageLines", () => {
  const lines = ["boot", "ERROR one", "ok", "ERROR two"]

  test("offset and limit page through the buffer", () => {
    const page = pageLines(lines, { offset: 1, limit: 2 })
    expect(page).toEqual({ ok: true, lines: ["ERROR one", "ok"], total: 4 })
  })

  test("a pattern filters first, so offset applies to the matches", () => {
    const page = pageLines(lines, { pattern: "ERROR", offset: 1, limit: 1 })
    expect(page).toEqual({ ok: true, lines: ["ERROR two"], total: 2 })
  })

  test("an invalid pattern is reported, not thrown", () => {
    const page = pageLines(lines, { pattern: "(" })
    expect(page.ok).toBe(false)
    if (!page.ok) expect(page.error).toStartWith("invalid pattern:")
  })
})
