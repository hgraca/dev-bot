// =============================================================================
// src/harnesses/opencode-v2/hooks/pty/sessions.ts
// The PTY session registry: spawn, buffer, read, kill.
//
// Holds the state the five tools act on and the RPC publishes. The spawn
// function is injected, so the registry carries no `bun-pty` import and a test
// drives it with a fake child.
// =============================================================================

import { sessionInfo, type PtyRecord } from "./lib"
import type { PtySessionInfo, PtyStatus } from "./rpc"

/** The part of a `bun-pty` child this registry uses. */
export interface PtyHandle {
  readonly pid?: number
  write(data: string): void
  kill(): void
  onData(handler: (chunk: string) => void): void
  onExit(handler: (exit: { exitCode: number }) => void): void
}

export interface SpawnOptions {
  name: string
  cols: number
  rows: number
  cwd: string
}

export type SpawnPty = (shell: string, args: string[], options: SpawnOptions) => PtyHandle

export type Result<T> = { ok: true; value: T } | { ok: false; error: string }

/** Bounds the memory one runaway process can cost the harness. */
const MAX_BUFFER_LINES = 50_000
/** A chunk without a newline is capped too: lines bound one axis, not bytes. */
const MAX_PARTIAL_CHARS = 64_000
/** Finished sessions kept for their output, oldest dropped first. A record and
 *  its buffer are only worth keeping while someone may still read them. */
const MAX_FINISHED = 20
const DEFAULT_COLS = 120
const DEFAULT_ROWS = 40

interface Session {
  record: PtyRecord
  lines: string[]
  /** The tail of a chunk that has no newline yet. */
  partial: string
  handle: PtyHandle
}

export interface PtySessions {
  spawn(input: {
    command: string
    cwd?: string
    cols?: number
    rows?: number
    title?: string
    parentSessionId?: string
  }): Result<PtySessionInfo>
  list(): PtySessionInfo[]
  write(id: string, data: string): Result<string>
  buffer(id: string): Result<{ status: PtyStatus; exitCode: number | null; lines: string[] }>
  kill(id: string, cleanup: boolean): Result<string>
  /** Kills every live child; called when the plugin unloads. */
  close(): void
}

export function createPtySessions(input: {
  spawn: SpawnPty
  shell: string
  /** Default working directory, the project root. */
  root: string
  now?: () => number
  newId?: () => string
}): PtySessions {
  const sessions = new Map<string, Session>()
  const now = input.now ?? (() => Date.now())
  const newId = input.newId ?? (() => `pty_${Math.random().toString(36).slice(2, 10)}`)

  /** Keep the published count in step with what a reader can actually see: a
   *  prompt with no newline is still a line on screen. */
  const refreshCount = (session: Session) => {
    session.record.lineCount = session.lines.length + (session.partial ? 1 : 0)
  }

  const appendChunk = (session: Session, chunk: string) => {
    // A PTY translates every newline to CRLF, so the carriage return has to go
    // or it rides along in every line, the panel renders it, and a `$`-anchored
    // pattern never matches.
    const parts = (session.partial + chunk.replace(/\r\n/g, "\n")).split("\n")
    session.partial = parts.pop() ?? ""
    if (session.partial.length > MAX_PARTIAL_CHARS) {
      session.partial = session.partial.slice(-MAX_PARTIAL_CHARS)
    }
    session.lines.push(...parts)
    trim(session)
    refreshCount(session)
  }

  const trim = (session: Session) => {
    if (session.lines.length > MAX_BUFFER_LINES) {
      session.lines.splice(0, session.lines.length - MAX_BUFFER_LINES)
    }
    refreshCount(session)
  }

  /** Drop the finished sessions that stopped longest ago once the kept set
   *  outgrows its cap. Ordered by exit time, not by insertion: a long-running
   *  session that started first can finish last, and it must not be the one
   *  discarded. */
  const pruneFinished = () => {
    const finished = [...sessions.values()]
      .filter((s) => s.record.exitAt !== null)
      .sort((a, b) => Number(a.record.exitAt) - Number(b.record.exitAt))
    for (const session of finished.slice(0, Math.max(0, finished.length - MAX_FINISHED))) {
      sessions.delete(session.record.id)
    }
  }

  return {
    spawn(spawnInput) {
      const command = String(spawnInput.command ?? "").trim()
      if (!command) return { ok: false, error: "command is required" }

      const cwd = spawnInput.cwd || input.root
      const handle = input.spawn(input.shell, ["-lc", command], {
        name: "xterm-256color",
        cols: Number(spawnInput.cols ?? DEFAULT_COLS),
        rows: Number(spawnInput.rows ?? DEFAULT_ROWS),
        cwd,
      })

      const record: PtyRecord = {
        id: newId(),
        title: spawnInput.title || command,
        command,
        workdir: cwd,
        pid: handle.pid ?? 0,
        parentSessionId: String(spawnInput.parentSessionId ?? ""),
        createdAt: now(),
        exitAt: null,
        exitCode: null,
        killed: false,
        lineCount: 0,
      }
      const session: Session = { record, lines: [], partial: "", handle }
      sessions.set(record.id, session)
      pruneFinished()

      handle.onData((chunk: string) => appendChunk(session, chunk))
      handle.onExit(({ exitCode }: { exitCode: number }) => {
        // A command can end without a trailing newline; that last line is still
        // output the caller has to see.
        if (session.partial) {
          session.lines.push(session.partial)
          session.partial = ""
          trim(session)
          refreshCount(session)
        }
        session.record.exitAt = now()
        session.record.exitCode = exitCode
        pruneFinished()
      })

      return { ok: true, value: sessionInfo(record) }
    },

    list() {
      return [...sessions.values()].map((session) => sessionInfo(session.record))
    },

    write(id, data) {
      const session = sessions.get(id)
      if (!session) return { ok: false, error: `no PTY session '${id}'` }
      if (session.record.exitAt !== null) return { ok: false, error: `session '${id}' has exited` }
      session.handle.write(String(data ?? ""))
      return { ok: true, value: "ok" }
    },

    buffer(id) {
      const session = sessions.get(id)
      if (!session) return { ok: false, error: `no PTY session '${id}'` }
      const info = sessionInfo(session.record)
      // The unterminated tail is included: a prompt such as `Password: ` never
      // ends with a newline, and hiding it would leave the reader with an empty
      // view of a session that is waiting for them.
      const lines = session.partial ? [...session.lines, session.partial] : [...session.lines]
      // A copy: each caller windows the buffer its own way, and neither may
      // mutate what the other reads.
      return {
        ok: true,
        value: { status: info.status, exitCode: info.exitCode, lines },
      }
    },

    kill(id, cleanup) {
      const session = sessions.get(id)
      if (!session) return { ok: false, error: `no PTY session '${id}'` }
      if (session.record.exitAt === null) {
        session.record.killed = true
        try {
          session.handle.kill()
        } catch {
          // Already gone: the record still has to be dropped on cleanup.
        }
      }
      if (cleanup) {
        sessions.delete(id)
        return { ok: true, value: `killed and removed ${id}` }
      }
      return { ok: true, value: `killed ${id}` }
    },

    close() {
      for (const session of sessions.values()) {
        // A child that exited on its own leaves its handle closed on bun-pty's
        // side; killing it again is the one call that could reach a stale
        // native pointer, so unload only stops what is still running.
        if (session.record.exitAt !== null) continue
        try {
          session.handle.kill()
        } catch {
          // Already gone.
        }
      }
      sessions.clear()
    },
  }
}
