// =============================================================================
// src/harnesses/opencode-v2/hooks/pty/index.ts
// Agent PTY capability for OpenCode 2.x: the five tools, plus the RPC the TUI
// part reads.
//
// v1 shipped `opencode-pty@0.3.6`, whose published builds still depend on the
// V1 plugin SDK (@opencode-ai/plugin ^1.3.13) — and V1 plugin implementations do
// not run on a V2 host, so there is no upstream build to pin. This module
// provides the same five tools directly against `ctx.tool.transform`, keeps the
// sessions in its own registry, and publishes them over `PtyRpc`.
//
// It depends on `bun-pty`, which the scaffold's package.json declares. When that
// dependency is absent the tools still register and fail with an actionable
// message instead of disappearing from the model's toolset.
// =============================================================================

import { Plugin } from "@opencode/plugin"
import { appendFileSync, mkdirSync } from "node:fs"
import { dirname, join } from "node:path"
import { filterByParent, pageLines, parentSessionIdOf, tailLines } from "./lib"
import { PtyRpc } from "./rpc"
import { createPtySessions, type SpawnPty } from "./sessions"

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

    let spawnPty: SpawnPty | null = null
    let loadError = ""
    // The shim re-exports this module from its own location, so a bare specifier
    // resolves against the dev-bot checkout, not the project's .opencode. Try the
    // bare specifier first (a global install), then the project-local one.
    const projectDir = ctx.location?.project?.canonical || ctx.location?.directory || process.cwd()
    const candidates = ["bun-pty", join(projectDir, ".opencode", "node_modules", "bun-pty")]
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

    // Without bun-pty every executor refuses with the same actionable message;
    // the registry is still built so the RPC answers an empty list rather than
    // failing, which keeps the sidebar inert instead of broken.
    const sessions = createPtySessions({
      spawn: (shell, args, options) => {
        if (!spawnPty) throw new Error(loadError)
        return spawnPty(shell, args, options)
      },
      shell: process.env.SHELL || "/bin/bash",
      root,
    })

    const unavailable = (): { content: string } => ({
      content: `PTY support is unavailable: ${loadError}. Run \`bun install\` in .opencode/ so bun-pty is present, then restart the harness.`,
    })

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
        execute: async (input: any, context: any) => {
          if (!spawnPty) return unavailable()
          const result = sessions.spawn({
            command: String(input?.command ?? ""),
            cwd: input?.cwd === undefined ? undefined : String(input.cwd),
            cols: input?.cols === undefined ? undefined : Number(input.cols),
            rows: input?.rows === undefined ? undefined : Number(input.rows),
            title: input?.title === undefined ? undefined : String(input.title),
            // The spawning agent session is the context of the call, not an
            // argument the model supplies (upstream PR #91 exposed the field).
            parentSessionId: parentSessionIdOf(context),
          })
          if (!result.ok) return { content: result.error }
          log(`spawned ${result.value.id} pid=${result.value.pid}: ${result.value.command}`)
          // Content only: a tool that returns `output` must declare an output
          // schema, and without one the whole result fails to serialise.
          return { content: `spawned ${result.value.id} (pid ${result.value.pid})` }
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
          const result = sessions.write(String(input?.id ?? ""), String(input?.data ?? ""))
          return { content: result.ok ? result.value : result.error }
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
          const id = String(input?.id ?? "")
          // The tool pages by matches; the RPC returns a tail. The registry
          // hands out the raw buffer, so each caller applies its own window.
          const buffer = sessions.buffer(id)
          if (!buffer.ok) return { content: buffer.error }
          const page = pageLines(buffer.value.lines, {
            offset: input?.offset === undefined ? undefined : Number(input.offset),
            limit: input?.limit === undefined ? undefined : Number(input.limit),
            pattern: input?.pattern === undefined ? undefined : String(input.pattern),
          })
          if (!page.ok) return { content: page.error }
          const header = `total=${page.total} offset=${Math.max(0, Number(input?.offset ?? 0))} status=${buffer.value.status} exitCode=${buffer.value.exitCode ?? "-"}`
          return { content: `${header}\n${page.lines.join("\n")}` }
        },
      })

      editor.add({
        name: "list",
        description: "List active PTY sessions with their exit state.",
        input: { type: "object", properties: {}, additionalProperties: false },
        execute: async () => {
          const list = sessions.list()
          if (list.length === 0) return { content: "no PTY sessions" }
          // The owner is what lets a model tell its own PTYs from a subagent's.
          const rows = list.map(
            (s) =>
              `${s.id} pid=${s.pid} lines=${s.lineCount} status=${s.status} exitCode=${s.exitCode ?? "-"} parent=${s.parentSessionId || "-"}`,
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
          const result = sessions.kill(String(input?.id ?? ""), input?.cleanup === true)
          if (!result.ok) log(`kill failed: ${result.error}`)
          return { content: result.ok ? result.value : result.error }
        },
      })
    })

    // A host without the RPC domain still gets the tools; the sidebar is the
    // only surface that needs this, so its absence is a logged degradation.
    let registration: { dispose: () => Promise<void> } | undefined
    if (typeof ctx.rpc?.register !== "function") {
      log("WARN: host exposes no rpc domain — the PTY sidebar will show no sessions")
    } else {
      try {
        registration = await ctx.rpc.register(PtyRpc, {
          list: async (rpcInput: any) => {
            const parent = typeof rpcInput?.parentSessionId === "string" ? rpcInput.parentSessionId : ""
            return filterByParent(sessions.list(), parent)
          },
          read: async (rpcInput: any) => {
            const id = String(rpcInput?.id ?? "")
            const buffer = sessions.buffer(id)
            if (!buffer.ok) throw new Error(buffer.error)
            const wanted = Math.max(1, Number(rpcInput?.lines ?? 200))
            return {
              id,
              status: buffer.value.status,
              exitCode: buffer.value.exitCode,
              total: buffer.value.lines.length,
              lines: tailLines(buffer.value.lines, wanted),
            }
          },
          kill: async (rpcInput: any) => {
            const id = String(rpcInput?.id ?? "")
            const result = sessions.kill(id, rpcInput?.cleanup === true)
            if (!result.ok) throw new Error(result.error)
            return { id, message: result.value }
          },
        })
      } catch (e) {
        log(`WARN: rpc registration failed — ${e instanceof Error ? e.message : String(e)}`)
      }
    }

    return async () => {
      await registration?.dispose()
      sessions.close()
    }
  },
})
