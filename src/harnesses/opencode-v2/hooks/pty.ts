// src/harnesses/opencode-v2/hooks/pty.ts
// Agent PTY capability for OpenCode 2.x.
//
// v1 shipped `opencode-pty@0.3.6`, whose published builds still depend on the
// V1 plugin SDK (@opencode-ai/plugin ^1.3.13) — and V1 plugin implementations do
// not run on a V2 host, so there is no upstream build to pin. This module
// provides the same five tools directly against `ctx.tool.transform`.
//
// It depends on `bun-pty`, which the scaffold's package.json declares. When that
// dependency is absent the tools still register and fail with an actionable
// message instead of disappearing from the model's toolset.

import { Plugin } from "@opencode/plugin"
import { appendFileSync, mkdirSync } from "node:fs"
import { dirname, join } from "node:path"

const MAX_BUFFER_LINES = 50_000
const DEV_BOT_ROOT = join(import.meta.dir, "../../../..")

interface PtySession {
  id: string
  pid: number
  pty: any
  lines: string[]
  partial: string
  exited: boolean
  exitCode: number | null
}

const sessions = new Map<string, PtySession>()

function appendChunk(session: PtySession, chunk: string) {
  const text = session.partial + chunk
  const parts = text.split("\n")
  session.partial = parts.pop() ?? ""
  for (const line of parts) session.lines.push(line)
  if (session.lines.length > MAX_BUFFER_LINES) {
    session.lines.splice(0, session.lines.length - MAX_BUFFER_LINES)
  }
}

export default Plugin.define({
  id: "devbot-pty",
  async setup(ctx: any) {
    const root: string = ctx.location?.project?.canonical || ctx.location?.directory || process.cwd()
    const logFile = join(root, ".agents", "logs", "pty.log")

    const log = (line: string) => {
      try {
        mkdirSync(dirname(logFile), { recursive: true })
        appendFileSync(logFile, `${new Date().toISOString()} [pty] ${line}\n`)
      } catch {
        // Logging must never break the harness.
      }
    }

    let spawnPty: ((cmd: string, args: string[], opts: any) => any) | null = null
    let loadError = ""
    // The shim re-exports this module from its own location, so a bare specifier
    // resolves against the dev-bot checkout, not the project's .opencode. Try the
    // bare specifier first (a global install), then the project-local one.
    const projectDir = ctx.location?.project?.canonical || ctx.location?.directory || process.cwd()
    const candidates = [
      "bun-pty",
      join(projectDir, ".opencode", "node_modules", "bun-pty"),
    ]
    for (const spec of candidates) {
      try {
        const mod: any = await import(spec)
        const candidate = mod?.spawn ?? mod?.default?.spawn ?? null
        if (candidate) {
          spawnPty = candidate
          loadError = ""
          break
        }
        loadError = `bun-pty at ${spec} exports no spawn()`
      } catch (e) {
        loadError = e instanceof Error ? e.message : String(e)
      }
    }
    if (loadError) log(`WARN: PTY tools unavailable — ${loadError}`)

    const unavailable = (): { content: string } => ({
      content: `PTY support is unavailable: ${loadError}. Run \`bun install\` in .opencode/ so bun-pty is present, then restart the harness.`,
    })

    const findByID = (id: string): PtySession | null => sessions.get(id) ?? null

    await ctx.tool.transform((editor: any) => {
      editor.namespace({
        name: "pty",
        description: "Interactive pseudo-terminals (non-blocking, process survives between calls)",
      })

      editor.add({
        name: "spawn",
        description:
          "Start a command in a pseudo-terminal. Returns an id for pty_write / pty_read / pty_kill. Output arrives asynchronously — poll pty_read until it appears. Prefer the bash tool for short deterministic commands.",
        input: {
          type: "object",
          properties: {
            command: { type: "string", description: "Command line to run" },
            cwd: { type: "string", description: "Working directory (defaults to the project root)" },
            cols: { type: "number", description: "Terminal width (default 120)" },
            rows: { type: "number", description: "Terminal height (default 40)" },
            title: { type: "string", description: "Human-readable session title" },
          },
          required: ["command"],
          additionalProperties: false,
        },
        execute: async (input: any) => {
          if (!spawnPty) return unavailable()
          const id = `pty_${Math.random().toString(36).slice(2, 10)}`
          const command = String(input?.command ?? "")
          if (!command) return { content: "command is required" }
          const shell = process.env.SHELL || "/bin/bash"
          const pty = spawnPty(shell, ["-lc", command], {
            name: "xterm-256color",
            cols: Number(input?.cols ?? 120),
            rows: Number(input?.rows ?? 40),
            cwd: String(input?.cwd ?? root),
          })
          const session: PtySession = {
            id,
            pid: pty?.pid ?? 0,
            pty,
            lines: [],
            partial: "",
            exited: false,
            exitCode: null,
          }
          pty.onData((chunk: string) => appendChunk(session, chunk))
          pty.onExit(({ exitCode }: { exitCode: number }) => {
            // A command can end without a trailing newline; that last line is
            // still output the caller has to see.
            if (session.partial) {
              session.lines.push(session.partial)
              session.partial = ""
              if (session.lines.length > MAX_BUFFER_LINES) {
                session.lines.splice(0, session.lines.length - MAX_BUFFER_LINES)
              }
            }
            session.exited = true
            session.exitCode = exitCode
          })
          sessions.set(id, session)
          log(`spawned ${id} pid=${session.pid}: ${command}`)
          // Content only: a tool that returns `output` must declare an output
          // schema, and without one the whole result fails to serialise.
          return { content: `spawned ${id} (pid ${session.pid})` }
        },
      })

      editor.add({
        name: "write",
        description: "Send input to a PTY session. Include \\n to submit a line.",
        input: {
          type: "object",
          properties: {
            id: { type: "string" },
            data: { type: "string", description: "Raw input, escape sequences allowed" },
          },
          required: ["id", "data"],
          additionalProperties: false,
        },
        execute: async (input: any) => {
          const session = findByID(String(input?.id ?? ""))
          if (!session) return { content: `no PTY session '${input?.id}'` }
          if (session.exited) return { content: `session '${session.id}' has exited` }
          session.pty.write(String(input?.data ?? ""))
          return { content: "ok" }
        },
      })

      editor.add({
        name: "read",
        description: "Read buffered output from a PTY session, optionally filtered by a regular expression.",
        input: {
          type: "object",
          properties: {
            id: { type: "string" },
            offset: { type: "number", description: "0-based line offset (default 0)" },
            limit: { type: "number", description: "Maximum lines (default 200)" },
            pattern: { type: "string", description: "Only matching lines (case-sensitive regex)" },
          },
          required: ["id"],
          additionalProperties: false,
        },
        execute: async (input: any) => {
          const session = findByID(String(input?.id ?? ""))
          if (!session) return { content: `no PTY session '${input?.id}'` }
          let lines = session.lines
          if (input?.pattern) {
            try {
              const re = new RegExp(String(input.pattern))
              lines = lines.filter((line) => re.test(line))
            } catch (e) {
              return { content: `invalid pattern: ${e instanceof Error ? e.message : String(e)}` }
            }
          }
          const offset = Math.max(0, Number(input?.offset ?? 0))
          const limit = Math.max(1, Number(input?.limit ?? 200))
          const page = lines.slice(offset, offset + limit)
          const header = `total=${lines.length} offset=${offset} exited=${session.exited} exitCode=${session.exitCode ?? "-"}`
          return { content: `${header}\n${page.join("\n")}` }
        },
      })

      editor.add({
        name: "list",
        description: "List active PTY sessions with their exit state.",
        input: { type: "object", properties: {}, additionalProperties: false },
        execute: async () => {
          if (sessions.size === 0) return { content: "no PTY sessions" }
          const rows = [...sessions.values()].map(
            (s) => `${s.id} pid=${s.pid} lines=${s.lines.length} exited=${s.exited} exitCode=${s.exitCode ?? "-"}`,
          )
          return { content: rows.join("\n") }
        },
      })

      editor.add({
        name: "kill",
        description: "Terminate a PTY session and drop it from the registry.",
        input: {
          type: "object",
          properties: {
            id: { type: "string" },
            cleanup: { type: "boolean", description: "Drop the session entirely (default false)" },
          },
          required: ["id"],
          additionalProperties: false,
        },
        execute: async (input: any) => {
          const id = String(input?.id ?? "")
          const session = findByID(id)
          if (!session) return { content: `no PTY session '${id}'` }
          try {
            session.pty.kill()
          } catch (e) {
            log(`kill ${id} failed: ${e instanceof Error ? e.message : String(e)}`)
          }
          if (input?.cleanup === true) {
            sessions.delete(id)
            return { content: `killed and removed ${id}` }
          }
          return { content: `killed ${id}` }
        },
      })
    })

    return () => {
      for (const session of sessions.values()) {
        try {
          session.pty.kill()
        } catch {
          // Already gone.
        }
      }
      sessions.clear()
    }
  },
})
