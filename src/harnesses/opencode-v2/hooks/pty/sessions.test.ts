// =============================================================================
// src/harnesses/opencode-v2/hooks/pty/sessions.test.ts
// The registry behind the five PTY tools: spawn, buffering, read, write, kill.
//
// Driven through a fake child, so the tool surface is exercised without a real
// `bun-pty` and without spawning anything.
// =============================================================================

import { describe, expect, test } from "bun:test"
import { createPtySessions, type SpawnOptions } from "./sessions"

class FakePty {
  readonly pid = 4242
  readonly written: string[] = []
  kills = 0
  private data: Array<(chunk: string) => void> = []
  private exits: Array<(exit: { exitCode: number }) => void> = []

  write(data: string) {
    this.written.push(data)
  }

  kill() {
    this.kills += 1
  }

  onData(handler: (chunk: string) => void) {
    this.data.push(handler)
  }

  onExit(handler: (exit: { exitCode: number }) => void) {
    this.exits.push(handler)
  }

  emit(chunk: string) {
    for (const handler of this.data) handler(chunk)
  }

  exit(code: number) {
    for (const handler of this.exits) handler({ exitCode: code })
  }
}

function harness() {
  const handles: FakePty[] = []
  const spawns: Array<{ shell: string; args: string[]; options: SpawnOptions }> = []
  let clock = Date.parse("2026-11-17T10:00:00.000Z")

  const sessions = createPtySessions({
    spawn: (shell, args, options) => {
      const handle = new FakePty()
      handles.push(handle)
      spawns.push({ shell, args, options })
      return handle
    },
    shell: "/bin/bash",
    root: "/project",
    now: () => clock,
    newId: () => `pty_${handles.length + 1}`,
  })

  return {
    sessions,
    handles,
    spawns,
    tick: (ms: number) => {
      clock += ms
    },
  }
}

describe("spawn", () => {
  test("runs the command through a login shell in the project root", () => {
    const { sessions, spawns } = harness()
    const result = sessions.spawn({ command: "npm run dev" })

    expect(result.ok).toBe(true)
    expect(spawns[0].shell).toBe("/bin/bash")
    expect(spawns[0].args).toEqual(["-lc", "npm run dev"])
    expect(spawns[0].options.cwd).toBe("/project")
    expect(spawns[0].options.name).toBe("xterm-256color")
  })

  test("records the spawning agent session, and defaults the title to the command", () => {
    const { sessions } = harness()
    const result = sessions.spawn({ command: "npm run dev", parentSessionId: "ses_parent" })

    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.value.parentSessionId).toBe("ses_parent")
    expect(result.value.title).toBe("npm run dev")
    expect(result.value.status).toBe("running")
    expect(result.value.pid).toBe(4242)
  })

  test("an explicit cwd and title win", () => {
    const { sessions } = harness()
    const result = sessions.spawn({ command: "npm run dev", cwd: "/elsewhere", title: "Dev Server" })

    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.value.workdir).toBe("/elsewhere")
    expect(result.value.title).toBe("Dev Server")
  })

  test("an empty command is refused instead of spawning a shell", () => {
    const { sessions, handles } = harness()
    const result = sessions.spawn({ command: "   " })

    expect(result).toEqual({ ok: false, error: "command is required" })
    expect(handles).toHaveLength(0)
  })
})

describe("buffering", () => {
  test("chunks become lines without the trailing newline", () => {
    const { sessions, handles } = harness()
    const id = sessions.spawn({ command: "x" })
    if (!id.ok) throw new Error(id.error)

    handles[0].emit("hello\nwor")
    handles[0].emit("ld\n")

    const buffer = sessions.buffer(id.value.id)
    expect(buffer.ok).toBe(true)
    if (!buffer.ok) return
    expect(buffer.value.lines).toEqual(["hello", "world"])
  })

  test("an unterminated last line is kept when the child exits", () => {
    const { sessions, handles } = harness()
    const id = sessions.spawn({ command: "x" })
    if (!id.ok) throw new Error(id.error)

    handles[0].emit("no newline at the end")
    handles[0].exit(0)

    const buffer = sessions.buffer(id.value.id)
    if (!buffer.ok) throw new Error(buffer.error)
    expect(buffer.value.lines).toEqual(["no newline at the end"])
    expect(buffer.value.status).toBe("exited")
    expect(buffer.value.exitCode).toBe(0)
  })

  test("a PTY's CRLF endings lose the carriage return", () => {
    // A terminal translates every newline to CRLF; keeping the \r would render
    // as a control char and break a `$`-anchored pattern.
    const { sessions, handles } = harness()
    const id = sessions.spawn({ command: "x" })
    if (!id.ok) throw new Error(id.error)

    handles[0].emit("hello\r\nworld\r\n")
    const buffer = sessions.buffer(id.value.id)
    if (!buffer.ok) throw new Error(buffer.error)
    expect(buffer.value.lines).toEqual(["hello", "world"])
  })

  test("the line count the info publishes follows the buffer", () => {
    const { sessions, handles } = harness()
    const id = sessions.spawn({ command: "x" })
    if (!id.ok) throw new Error(id.error)
    handles[0].emit("a\nb\nc\n")

    expect(sessions.list()[0].lineCount).toBe(3)
  })

  test("a caller cannot mutate the registry's buffer", () => {
    const { sessions, handles } = harness()
    const id = sessions.spawn({ command: "x" })
    if (!id.ok) throw new Error(id.error)
    handles[0].emit("keep\n")

    const buffer = sessions.buffer(id.value.id)
    if (!buffer.ok) throw new Error(buffer.error)
    buffer.value.lines.push("mutated")

    const again = sessions.buffer(id.value.id)
    if (!again.ok) throw new Error(again.error)
    expect(again.value.lines).toEqual(["keep"])
  })
})

describe("exit", () => {
  test("stamps the exit time and code, which makes the session exited", () => {
    const { sessions, handles, tick } = harness()
    const id = sessions.spawn({ command: "x" })
    if (!id.ok) throw new Error(id.error)
    tick(1_500)
    handles[0].exit(3)

    const info = sessions.list()[0]
    expect(info.status).toBe("exited")
    expect(info.exitCode).toBe(3)
    expect(info.exitAt).not.toBeNull()
  })
})

describe("retention", () => {
  test("finished sessions are bounded, oldest dropped first", () => {
    // A record and its buffer are only worth keeping while someone may read
    // them; an unbounded list grows for the life of the process.
    const { sessions, handles } = harness()
    for (let i = 0; i < 25; i++) {
      const spawned = sessions.spawn({ command: `job ${i}` })
      if (!spawned.ok) throw new Error(spawned.error)
      handles[i].emit(`ran ${i}\n`)
      handles[i].exit(0)
    }
    const kept = sessions.list()
    expect(kept).toHaveLength(20)
    expect(kept[0].command).toBe("job 5")
    expect(kept.at(-1)?.command).toBe("job 24")
  })

  test("a session that started first but finished last is kept", () => {
    // Insertion order is not exit order: the long-running job is the newest
    // finished session and must survive the cap.
    const { sessions, handles, tick } = harness()
    const longRunning = sessions.spawn({ command: "long" })
    if (!longRunning.ok) throw new Error(longRunning.error)
    for (let i = 0; i < 24; i++) {
      const spawned = sessions.spawn({ command: `job ${i}` })
      if (!spawned.ok) throw new Error(spawned.error)
      tick(100)
      handles[i + 1].exit(0)
    }
    tick(100)
    handles[0].exit(0)

    const kept = sessions.list().map((s) => s.command)
    expect(kept).toHaveLength(20)
    // The five that finished first are the ones dropped, whatever their start
    // order was.
    expect(kept).toContain("long")
    expect(kept).toContain("job 5")
    expect(kept).not.toContain("job 4")
  })

  test("a running session is never dropped", () => {
    const { sessions, handles } = harness()
    const live = sessions.spawn({ command: "server" })
    if (!live.ok) throw new Error(live.error)
    for (let i = 0; i < 24; i++) {
      const spawned = sessions.spawn({ command: `job ${i}` })
      if (!spawned.ok) throw new Error(spawned.error)
      handles[i + 1].exit(0)
    }
    expect(sessions.list().some((s) => s.id === live.value.id)).toBe(true)
  })
})

describe("write", () => {
  test("forwards the data, so a caller can answer a prompt", () => {
    const { sessions, handles } = harness()
    const id = sessions.spawn({ command: "x" })
    if (!id.ok) throw new Error(id.error)

    expect(sessions.write(id.value.id, "yes\n")).toEqual({ ok: true, value: "ok" })
    expect(handles[0].written).toEqual(["yes\n"])
  })

  test("refuses an unknown id and an exited session", () => {
    const { sessions, handles } = harness()
    expect(sessions.write("pty_missing", "x").ok).toBe(false)

    const id = sessions.spawn({ command: "x" })
    if (!id.ok) throw new Error(id.error)
    handles[0].exit(0)
    const refused = sessions.write(id.value.id, "x")
    expect(refused.ok).toBe(false)
    if (!refused.ok) expect(refused.error).toContain("has exited")
  })
})

describe("kill", () => {
  test("marks the session killed, so the row does not read as a failure", () => {
    const { sessions, handles } = harness()
    const id = sessions.spawn({ command: "x" })
    if (!id.ok) throw new Error(id.error)

    expect(sessions.kill(id.value.id, false)).toEqual({ ok: true, value: `killed ${id.value.id}` })
    expect(handles[0].kills).toBe(1)

    handles[0].exit(143)
    expect(sessions.list()[0].status).toBe("killed")
  })

  test("cleanup drops the record, and a plain kill keeps the output readable", () => {
    const { sessions, handles } = harness()
    const id = sessions.spawn({ command: "x" })
    if (!id.ok) throw new Error(id.error)

    sessions.kill(id.value.id, false)
    expect(sessions.list()).toHaveLength(1)

    sessions.kill(id.value.id, true)
    expect(sessions.list()).toHaveLength(0)
    expect(sessions.buffer(id.value.id).ok).toBe(false)
    expect(handles[0].kills).toBe(2)
  })

  test("killing an exited session does not touch its process again", () => {
    // A natural exit leaves the handle open on bun-pty's side; a second kill is
    // only harmless because we do not issue one.
    const { sessions, handles } = harness()
    const id = sessions.spawn({ command: "x" })
    if (!id.ok) throw new Error(id.error)
    handles[0].exit(0)

    sessions.kill(id.value.id, false)
    expect(handles[0].kills).toBe(0)
    expect(sessions.list()[0].status).toBe("exited")
  })

  test("an unknown id is an error, not a crash", () => {
    const { sessions } = harness()
    expect(sessions.kill("pty_missing", true).ok).toBe(false)
  })
})

describe("close", () => {
  test("kills every live child when the plugin unloads", () => {
    const { sessions, handles } = harness()
    sessions.spawn({ command: "a" })
    sessions.spawn({ command: "b" })

    sessions.close()

    expect(handles.map((h) => h.kills)).toEqual([1, 1])
    expect(sessions.list()).toHaveLength(0)
  })

  test("a child that already exited is not killed again", () => {
    // bun-pty leaves a naturally exited handle closed; a second kill is the one
    // call that could reach a stale native pointer.
    const { sessions, handles } = harness()
    sessions.spawn({ command: "done" })
    sessions.spawn({ command: "live" })
    handles[0].exit(0)

    sessions.close()

    expect(handles.map((h) => h.kills)).toEqual([0, 1])
  })
})
