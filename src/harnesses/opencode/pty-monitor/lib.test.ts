// =============================================================================
// src/harnesses/opencode/pty-monitor/lib.test.ts
// Tests for the pure logic of the PTY monitor plugin.
//
// Every bug found while spiking lives in one of these functions, which is
// the whole reason they are extracted from the TUI wiring and tested here:
//   - parseServerUrl: the first regex matched a DOC PLACEHOLDER ("<url>") from
//     the transcript instead of the real origin
//   - latestServerUrl: taking the FIRST match returned a STALE port from an
//     earlier run, because the PTY server is reassigned a port every start
//   - decodeBuffer: /buffer/plain returns JSON { plain, byteLength }, not text,
//     and the content uses CRLF
//   - rowLabel / rowTone: purely presentational, but the sidebar depends on them
//   - isFinished / finishedSessions / clearActionLabel: decide what the removal
//     controls act on, so a wrong status set would kill a live session
// =============================================================================

import { describe, expect, test } from "bun:test"
import {
  bootstrapFailureCause,
  clearActionLabel,
  decodeBuffer,
  finishedSessions,
  formatDetail,
  formatDuration,
  headerLabel,
  isFinished,
  isPtyCommandSentinel,
  isPtyHealth,
  latestServerUrl,
  matchServerUrl,
  parseListeningPorts,
  ROW_BULLET,
  rowLabel,
  rowTone,
  runDurationMs,
  tail,
} from "./lib"

describe("matchServerUrl", () => {
  test("extracts a real origin", () => {
    expect(matchServerUrl("PTY Sessions Web Interface URL: http://[::1]:45037")).toBe(
      "http://[::1]:45037",
    )
  })

  test("ignores a doc placeholder with no scheme", () => {
    // This exact string appears in the transcript (the agent's own messages)
    // and was matched by the first, too-loose \S+ pattern.
    expect(matchServerUrl("PTY Sessions Web Interface URL: `<url>`.")).toBeNull()
  })

  test("ignores bracketed and regex-looking placeholders", () => {
    expect(matchServerUrl("PTY Sessions Web Interface URL: [PORT]")).toBeNull()
    expect(matchServerUrl("PTY Sessions Web Interface URL: (\\S+)/`.")).toBeNull()
  })

  test("returns null when there is no marker at all", () => {
    expect(matchServerUrl("nothing to see here")).toBeNull()
  })

  test("trims trailing punctuation and newlines", () => {
    expect(matchServerUrl("PTY Sessions Web Interface URL: http://[::1]:45037\nrest")).toBe(
      "http://[::1]:45037",
    )
  })

  test("accepts https", () => {
    expect(matchServerUrl("PTY Sessions Web Interface URL: https://example.test:1234")).toBe(
      "https://example.test:1234",
    )
  })

  test("handles non-string input", () => {
    expect(matchServerUrl(null)).toBeNull()
    expect(matchServerUrl(undefined)).toBeNull()
  })
})

describe("latestServerUrl", () => {
  test("takes the LAST match, not the first", () => {
    // The stale port is the real failure mode: the PTY server binds a fresh
    // port on every start, so an older message holds a dead origin.
    const texts = [
      "PTY Sessions Web Interface URL: http://[::1]:45037",
      "PTY Sessions Web Interface URL: http://[::1]:35657",
    ]
    expect(latestServerUrl(texts)).toBe("http://[::1]:35657")
  })

  test("skips texts with no match and keeps the newest", () => {
    expect(
      latestServerUrl([
        "PTY Sessions Web Interface URL: http://[::1]:45037",
        "unrelated message",
        null,
        "PTY Sessions Web Interface URL: `<url>`.",
      ]),
    ).toBe("http://[::1]:45037")
  })

  test("takes the last match within a single text", () => {
    expect(
      latestServerUrl([
        "URL: http://[::1]:1 then PTY Sessions Web Interface URL: http://[::1]:2",
      ]),
    ).toBe("http://[::1]:2")
  })

  test("returns null when nothing matches", () => {
    expect(latestServerUrl([])).toBeNull()
    expect(latestServerUrl(["nope", null])).toBeNull()
  })
})

describe("decodeBuffer", () => {
  test("reads the JSON envelope the endpoint actually returns", () => {
    expect(decodeBuffer({ plain: "a\r\nb", byteLength: 4 })).toBe("a\nb")
  })

  test("normalises CRLF to LF", () => {
    expect(decodeBuffer({ plain: "x\r\ny\r\n" })).toBe("x\ny\n")
  })

  test("accepts a raw string body", () => {
    expect(decodeBuffer("raw\r\ntext")).toBe("raw\ntext")
  })

  test("returns empty string for anything unusable", () => {
    expect(decodeBuffer(null)).toBe("")
    expect(decodeBuffer(undefined)).toBe("")
    expect(decodeBuffer({})).toBe("")
    expect(decodeBuffer({ plain: null })).toBe("")
    expect(decodeBuffer(42)).toBe("")
  })
})

describe("rowLabel", () => {
  test("the shared bullet is the one the built-in sidebar items use", () => {
    expect(ROW_BULLET).toBe("• ")
  })

  test("omits the bullet so the caller can colour it separately", () => {
    const label = rowLabel({ title: "dev server", status: "running", lineCount: 3 })
    expect(label).not.toContain("•")
    expect(label).toContain("dev server")
    expect(label).toContain("3L")
  })

  test("shows a running session's line count", () => {
    const label = rowLabel({ title: "dev server", status: "running", lineCount: 42 })
    expect(label).toContain("dev server")
    expect(label).toContain("42")
  })

  test("shows an exited session's exit code", () => {
    const label = rowLabel({ title: "build", status: "exited", exitCode: 0, lineCount: 7 })
    expect(label).toContain("build")
    expect(label).toContain("exit 0")
  })

  test("falls back when the title is missing", () => {
    expect(rowLabel({ status: "running" })).toContain("untitled")
  })

  test("truncates a long title so the sidebar stays readable", () => {
    const label = rowLabel({ title: "x".repeat(100), status: "running" })
    // Pinned to the constant, not a loose bound: the title column is 24, so the
    // truncated title is 23 characters plus the ellipsis.
    expect(label.startsWith("x".repeat(23) + "…")).toBe(true)
  })

  test("shows a short title in full, with no ellipsis", () => {
    const label = rowLabel({ title: "build", status: "running" })
    expect(label).not.toContain("…")
  })

  test("killing/killed show their status word, not a bogus exit code", () => {
    // opencode-pty has four states, not two; these carry no exitCode, and the
    // earlier code rendered them as the nonsensical "exit ?".
    expect(rowLabel({ title: "svc", status: "killing" })).toContain("killing")
    expect(rowLabel({ title: "svc", status: "killed" })).toContain("killed")
    expect(rowLabel({ title: "svc", status: "killing" })).not.toContain("exit")
  })

  test("an exited session with no exit code falls back to its status", () => {
    expect(rowLabel({ title: "svc", status: "exited" })).toContain("exited")
    expect(rowLabel({ title: "svc", status: "exited" })).not.toContain("exit ?")
  })

  test("tolerates a missing session", () => {
    expect(typeof rowLabel(undefined)).toBe("string")
  })
})

describe("rowTone", () => {
  test("a running session is 'success'", () => {
    expect(rowTone({ status: "running" })).toBe("success")
  })

  test("a finished session with a non-zero exit is 'error'", () => {
    expect(rowTone({ status: "exited", exitCode: 1 })).toBe("error")
    expect(rowTone({ status: "exited", exitCode: 130 })).toBe("error")
  })

  test("a clean exit is 'muted' — it succeeded, so it should not shout", () => {
    expect(rowTone({ status: "exited", exitCode: 0 })).toBe("muted")
  })

  test("killing/killed are 'muted'", () => {
    expect(rowTone({ status: "killing" })).toBe("muted")
    expect(rowTone({ status: "killed" })).toBe("muted")
  })

  test("unknown state is 'muted'", () => {
    expect(rowTone({ status: "exited" })).toBe("muted")
    expect(rowTone({})).toBe("muted")
    expect(rowTone(undefined)).toBe("muted")
  })
})

describe("tail", () => {
  test("returns everything when it already fits", () => {
    expect(tail("a\nb\nc", 5)).toBe("a\nb\nc")
    expect(tail("a\nb\nc", 3)).toBe("a\nb\nc")
  })

  test("keeps the NEWEST lines and marks the cut", () => {
    // The newest output is the interesting end — a tail that kept the oldest
    // lines would show a process's startup instead of what it is doing now.
    expect(tail("1\n2\n3\n4\n5", 2)).toBe("…\n4\n5")
  })

  test("handles empty and non-string input", () => {
    expect(tail("", 3)).toBe("")
    expect(tail(null, 3)).toBe("null")
  })
})

describe("formatDetail", () => {
  test("summarises pid, status, command and workdir", () => {
    const d = formatDetail({
      id: "pty_1",
      title: "dev server",
      command: "npm",
      args: ["run", "dev"],
      workdir: "/tmp/x",
      status: "running",
      pid: 1234,
      lineCount: 9,
    })
    expect(d).toContain("pty_1")
    expect(d).toContain("1234")
    expect(d).toContain("npm run dev")
    expect(d).toContain("/tmp/x")
  })

  test("tolerates a missing session", () => {
    expect(typeof formatDetail(undefined)).toBe("string")
  })

  test("never exceeds two lines — every header line costs the output a line", () => {
    const d = formatDetail({
      id: "pty_1",
      title: "t",
      command: "npm",
      args: ["run", "dev"],
      workdir: "/tmp/x",
      status: "running",
      pid: 1,
      lineCount: 2,
    })
    expect(d.split("\n").length).toBeLessThanOrEqual(2)
  })
})

// ── OS port discovery ────────────────────────────────────────────────────────
//
// The PTY server binds a RANDOM port and publishes it only by posting a message
// into the session. Triggering that command is what litters the transcript, so
// the port is read from the OS instead: /proc/self/net/tcp6 lists listening
// sockets, and /proc/self/fd says which of them belong to this process. Parsing
// is pure, so these tests use the real /proc format as a fixture.

const TCP6_HEADER =
  "  sl  local_address                         remote_address                        st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode"

// ::1:37281 (01000000 tail) LISTEN, inode 45191672  — the PTY server
const TCP6_PTY = `   0: 00000000000000000000000001000000:91A1 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 45191672 1 0000000000000000 100 0 0 10 0`
// ::1:631 LISTEN, inode 999 — CUPS, a different process, so NOT in ownInodes
const TCP6_CUPS = `   1: 00000000000000000000000001000000:0277 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 14566476 1 0000000000000000 100 0 0 10 0`
// an ESTABLISHED (01) socket must be ignored even if we own it
const TCP6_ESTABLISHED = `   2: 00000000000000000000000001000000:91A1 00000000000000000000000001000000:C350 01 00000000:00000000 00:00000000 00000000  1000        0 45191672 1 0000000000000000 20 4 30 10 -1`

describe("parseListeningPorts", () => {
  test("finds our own listening port and ignores other processes'", () => {
    const ports = parseListeningPorts(
      [TCP6_HEADER, TCP6_PTY, TCP6_CUPS].join("\n"),
      "",
      new Set(["45191672"]),
    )
    expect(ports).toContain(37281)
    expect(ports).not.toContain(631)
  })

  test("ignores non-LISTEN sockets even when we own them", () => {
    const ports = parseListeningPorts(
      [TCP6_HEADER, TCP6_ESTABLISHED].join("\n"),
      "",
      new Set(["45191672"]),
    )
    expect(ports).toEqual([])
  })

  test("reads the IPv4 table too", () => {
    const tcp = [
      TCP6_HEADER,
      "   0: 0100007F:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000 0 777 1 0000000000000000 100 0 0 10 0",
    ].join("\n")
    expect(parseListeningPorts("", tcp, new Set(["777"]))).toEqual([8080])
  })

  test("deduplicates a port listening on both v4 and v6", () => {
    const tcp4Same = [
      TCP6_HEADER,
      "   0: 0100007F:91A1 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000 0 777 1 0000000000000000 100 0 0 10 0",
    ].join("\n")
    expect(
      parseListeningPorts([TCP6_HEADER, TCP6_PTY].join("\n"), tcp4Same, new Set(["45191672", "777"])),
    ).toEqual([37281])
  })

  test("returns ports from both tables when they differ", () => {
    const tcp4 = [
      TCP6_HEADER,
      "   0: 0100007F:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000 0 777 1 0000000000000000 100 0 0 10 0",
    ].join("\n")
    expect(
      parseListeningPorts([TCP6_HEADER, TCP6_PTY].join("\n"), tcp4, new Set(["45191672", "777"])),
    ).toEqual([37281, 8080])
  })

  test("tolerates missing or malformed input", () => {
    expect(parseListeningPorts("", "", new Set())).toEqual([])
    expect(parseListeningPorts(null, undefined, null)).toEqual([])
    expect(parseListeningPorts("garbage\nstill garbage", "", new Set(["1"]))).toEqual([])
  })
})

describe("isPtyHealth", () => {
  test("accepts the pty server's health payload", () => {
    expect(
      isPtyHealth({
        status: "healthy",
        timestamp: "2026-09-16T14:26:32.720Z",
        uptime: 64.01,
        sessions: { total: 1, active: 1 },
        websocket: { connections: 0 },
      }),
    ).toBe(true)
  })

  test("rejects anything else that happens to answer on the port", () => {
    expect(isPtyHealth(null)).toBe(false)
    expect(isPtyHealth("<!DOCTYPE HTML PUBLIC>")).toBe(false)
    expect(isPtyHealth({})).toBe(false)
    expect(isPtyHealth({ status: "ok" })).toBe(false)
    expect(isPtyHealth({ status: "healthy" })).toBe(false) // no sessions object
  })
})

describe("isPtyCommandSentinel", () => {
  // opencode-pty throws this to say "I handled the command" — after it has
  // already created the PTY server. Reading it as an error made a healthy
  // server report as unavailable, so it must never be stored as a failure.
  test("recognises the sentinel the command handler throws", () => {
    expect(isPtyCommandSentinel(new Error("Command handled by PTY plugin"))).toBe(true)
  })

  test("recognises it when the message carries extra context", () => {
    expect(
      isPtyCommandSentinel({ message: "Command handled by PTY plugin\n  at <anonymous>" }),
    ).toBe(true)
  })

  test("does not swallow a genuine failure", () => {
    expect(isPtyCommandSentinel(new Error("Command not found: pty-show-server-url"))).toBe(false)
    expect(isPtyCommandSentinel(new Error("fetch failed"))).toBe(false)
  })

  test("tolerates a thrown string or non-object", () => {
    expect(isPtyCommandSentinel("Command handled by PTY plugin")).toBe(true)
    expect(isPtyCommandSentinel(undefined)).toBe(false)
  })
})

describe("bootstrapFailureCause", () => {
  // This is the branch the panel's status text comes from, so a sentinel that
  // leaked through here is exactly the bug that reported a working server as
  // unavailable.
  test("reports nothing for the sentinel", () => {
    expect(bootstrapFailureCause(new Error("Command handled by PTY plugin"))).toBeNull()
    expect(bootstrapFailureCause({ message: "Command handled by PTY plugin" })).toBeNull()
  })

  test("keeps a genuine failure", () => {
    expect(bootstrapFailureCause(new Error("fetch failed"))).toContain("fetch failed")
  })

  test("stringifies a thrown non-Error", () => {
    expect(bootstrapFailureCause("boom")).toBe("boom")
  })
})

describe("isFinished", () => {
  test("a session that has stopped counts as finished", () => {
    expect(isFinished({ status: "exited" })).toBe(true)
    expect(isFinished({ status: "killed" })).toBe(true)
  })

  test("a live or transient session does not", () => {
    expect(isFinished({ status: "running" })).toBe(false)
    // `killing` is transient: the exit callback turns it into `killed`, so
    // treating it as finished would let a clear race the process teardown.
    expect(isFinished({ status: "killing" })).toBe(false)
  })

  test("tolerates junk instead of throwing", () => {
    expect(isFinished(null)).toBe(false)
    expect(isFinished(undefined)).toBe(false)
    expect(isFinished("exited")).toBe(false)
    expect(isFinished({})).toBe(false)
  })
})

describe("finishedSessions", () => {
  test("keeps only finished sessions, in their original order", () => {
    const list = [
      { id: "a", status: "running" },
      { id: "b", status: "exited" },
      { id: "c", status: "killed" },
      { id: "d", status: "killing" },
    ]
    expect(finishedSessions(list).map((s) => s.id)).toEqual(["b", "c"])
  })

  test("returns an empty list for anything that is not a list", () => {
    expect(finishedSessions(null)).toEqual([])
    expect(finishedSessions(undefined)).toEqual([])
    expect(finishedSessions({ sessions: [] })).toEqual([])
  })
})

describe("clearActionLabel", () => {
  test("names the action only when there is something to clear", () => {
    expect(clearActionLabel([{ status: "exited" }])).toBe("(clear finished)")
    expect(clearActionLabel([])).toBeNull()
  })

  test("stays hidden while every session is still live", () => {
    // The header must not offer a control that would delete nothing — and it
    // must never suggest that running sessions are in scope.
    expect(clearActionLabel([{ status: "running" }, { status: "killing" }])).toBeNull()
  })

  test("tolerates junk", () => {
    expect(clearActionLabel(null)).toBeNull()
  })
})

describe("headerLabel", () => {
  test("shows the chevron, the panel name and the status", () => {
    expect(headerLabel({ collapsed: false, status: "3 sessions" })).toBe("▼ PTY  3 sessions")
    expect(headerLabel({ collapsed: true, status: "3 sessions" })).toBe("▶ PTY  3 sessions")
  })

  test("renders without a status", () => {
    expect(headerLabel({})).toBe("▼ PTY  ")
  })
})

describe("formatDuration", () => {
  test("counts whole seconds below a minute", () => {
    expect(formatDuration(0)).toBe("0s")
    expect(formatDuration(999)).toBe("0s") // floors: 0.999s is not yet a second
    expect(formatDuration(1000)).toBe("1s")
    expect(formatDuration(12_000)).toBe("12s")
    expect(formatDuration(59_999)).toBe("59s")
  })

  test("pads the trailing unit past a minute", () => {
    expect(formatDuration(60_000)).toBe("1m 00s")
    expect(formatDuration(65_000)).toBe("1m 05s")
    expect(formatDuration(3_599_000)).toBe("59m 59s")
  })

  test("switches to hours with padded minutes past an hour", () => {
    expect(formatDuration(3_600_000)).toBe("1h 00m")
    expect(formatDuration(3_600_000 + 7 * 60_000)).toBe("1h 07m")
    expect(formatDuration(49 * 3_600_000 + 12 * 60_000)).toBe("49h 12m")
  })

  test("never renders a negative or unusable value", () => {
    // A clock can move backwards between the server and the panel.
    expect(formatDuration(-5000)).toBe("0s")
    expect(formatDuration(Number.NaN)).toBe("0s")
    expect(formatDuration(Number.POSITIVE_INFINITY)).toBe("0s")
    expect(formatDuration(null)).toBe("0s")
    expect(formatDuration(undefined)).toBe("0s")
    expect(formatDuration("60000")).toBe("0s")
  })
})

describe("runDurationMs", () => {
  const started = "2026-09-26T10:00:00.000Z"
  const startedMs = Date.parse(started)

  test("prefers the server's exit time when it reports one", () => {
    const exitAt = new Date(startedMs + 65_000).toISOString()
    // The observed time is deliberately different: the server's word wins.
    expect(
      runDurationMs({ createdAt: started, exitAt, observedFinishedAt: startedMs + 999_000, now: 0 }),
    ).toBe(65_000)
  })

  test("falls back to when this panel saw it stop", () => {
    // A server that predates `exitAt` reports none — the panel's own observation
    // is then the end, accurate to within one poll.
    expect(
      runDurationMs({ createdAt: started, observedFinishedAt: startedMs + 30_000, now: 0 }),
    ).toBe(30_000)
  })

  test("measures a running session to now", () => {
    expect(runDurationMs({ createdAt: started, now: startedMs + 5_000 })).toBe(5_000)
  })

  test("prefers the observation over now, so a finished figure stops moving", () => {
    expect(
      runDurationMs({
        createdAt: started,
        observedFinishedAt: startedMs + 10_000,
        now: startedMs + 90_000,
      }),
    ).toBe(10_000)
  })

  test("returns null when the server reported no usable start time", () => {
    expect(runDurationMs({ now: 1000 })).toBeNull()
    expect(runDurationMs({ createdAt: null, now: 1000 })).toBeNull()
    expect(runDurationMs({ createdAt: "not a date", now: 1000 })).toBeNull()
  })
})
