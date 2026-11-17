// src/harnesses/opencode-v2/hooks/mcp-sync.ts
// Writes a runtime MCP toggle back to the project config, so `devbot tool
// project-for-path` reports reality.
//
// V2 difference: enablement lives at `mcp.servers.<name>.disabled` (inverted
// from v1's `enabled`) and the runtime state comes from `ctx.mcp.list()`, which
// answers `{ location, data: Mcp.Server[] }`. The edit itself is delegated to
// this module's own v2config.py — the harness already requires python3, and a
// second implementation of the config splice in TypeScript is exactly the drift
// the shared helpers exist to prevent.
//
// The decisions (list shape, transition-only intent) live in ../mcp-sync-utils.ts.

import { Plugin } from "@opencode/plugin"
import { appendFileSync, mkdirSync } from "node:fs"
import { dirname, join } from "node:path"
import { acquireLock, releaseLock } from "../../../_shared/mcp-sync-lock.ts"
import { readJsoncFile } from "../on-hooks-utils"
import {
  devbotDirFromConfig,
  planWrites,
  serversFrom,
  statusMap,
  summary,
  type McpStatus,
} from "../mcp-sync-utils"

const POLL_MS = 2000
const DEV_BOT_ROOT = join(import.meta.dir, "../../../..")

// v2config.py `set-mcp-disabled` exit codes.
const WRITTEN = 0
const NOT_IN_PROJECT = 2

export default Plugin.define({
  id: "devbot-mcp-sync",
  async setup(ctx: any) {
    const root: string = ctx.location?.project?.canonical || ctx.location?.directory || process.cwd()
    const config = join(root, "opencode.jsonc")
    const helper = join(DEV_BOT_ROOT, "src", "harnesses", "opencode-v2", "lib", "v2config.py")
    const devbotDir = join(root, devbotDirFromConfig(readJsoncFile(join(root, ".devbot.project.jsonc"))))
    const logFile = join(devbotDir, "logs", "mcp-sync.log")
    // The lock lives beside the other generated state, not next to the config:
    // a lock directory appearing and vanishing in the project root every poll
    // was noise in `git status` and in the editor's file tree.
    const lockPath = join(devbotDir, "locks", "mcp-sync.lock")
    try {
      mkdirSync(dirname(lockPath), { recursive: true })
    } catch {
      // A read-only vault surfaces on the first write, which logs it.
    }

    let previous: Map<string, McpStatus> | null = null
    let busy = false
    const warned = new Set<string>()

    const log = (line: string) => {
      try {
        mkdirSync(dirname(logFile), { recursive: true })
        appendFileSync(logFile, `${new Date().toISOString()} [mcp-sync] ${line}\n`)
      } catch {
        // Logging must never break the harness.
      }
    }

    // Returns the helper's exit code and, for a real failure, its stderr: 0
    // written (or already correct), 2 the server belongs to another config.
    async function apply(name: string, disabled: boolean): Promise<{ code: number; error: string }> {
      // Two sessions (or a reinit) rewrite the same file; without the lock one
      // update is lost, so re-check on the next tick instead.
      const token = acquireLock(lockPath)
      if (!token) {
        log(`${name}: locked by another session — retrying`)
        return { code: 1, error: "locked by another session" }
      }
      try {
        const proc = Bun.spawn(
          ["python3", helper, "set-mcp-disabled", config, name, String(disabled)],
          { cwd: root, stdout: "pipe", stderr: "pipe" },
        )
        const code = await proc.exited
        // Keep the helper's stderr: a silent non-zero exit is what made a broken
        // write look like "nothing to do" for hours.
        let error = ""
        if (code !== 0 && code !== NOT_IN_PROJECT) {
          error = (await new Response(proc.stderr).text()).trim().split("\n").filter(Boolean).pop() ?? ""
        }
        return { code, error }
      } finally {
        releaseLock(lockPath, token)
      }
    }

    async function tick() {
      if (busy) return
      busy = true
      try {
        const servers = serversFrom(await ctx.mcp.list())
        if (servers.length === 0) return

        if (previous === null) {
          previous = statusMap(servers)
          log(`baseline: ${summary(previous)}`)
          return
        }

        const next = statusMap(servers)
        for (const write of planWrites(previous, servers)) {
          const { code, error } = await apply(write.name, write.disabled)
          if (code === WRITTEN) {
            warned.delete(write.name)
            log(`${write.name}: disabled=${write.disabled} → ${config}`)
          } else if (code === NOT_IN_PROJECT) {
            // Declared globally: this file has nothing to own.
            log(`${write.name}: not in ${config} — skipped`)
          } else {
            // Once per distinct failure, not once per 2s poll.
            const detail = `${write.name}: ${error || `helper exited ${code}`}`
            if (!warned.has(detail)) {
              warned.add(detail)
              log(`WARN: could not write ${detail}`)
            }
            // Keep the old status so the next tick retries the write.
            const before = previous.get(write.name)
            if (before !== undefined) next.set(write.name, before)
          }
        }
        previous = next
      } catch (e) {
        log(`WARN: ${e instanceof Error ? e.message : String(e)}`)
      } finally {
        busy = false
      }
    }

    log(`loaded for ${root}`)
    const timer = setInterval(() => void tick(), POLL_MS)
    void tick()
    return () => clearInterval(timer)
  },
})
