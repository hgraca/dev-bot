// src/harnesses/opencode-v2/hooks/mcp-sync.ts
// Writes a runtime MCP toggle back to the project config, so `devbot tool
// project-for-path` reports reality.
//
// V2 difference: enablement lives at `mcp.servers.<name>.disabled` (inverted
// from v1's `enabled`) and the runtime state comes from `ctx.mcp.list()` rather
// than an SDK `client.mcp.status()`. The edit itself is delegated to this
// module's own v2config.py — the harness already requires python3, and a second
// implementation of the config splice in TypeScript is exactly the drift the
// shared helpers exist to prevent.

import { Plugin } from "@opencode/plugin"
import { appendFileSync, mkdirSync } from "node:fs"
import { dirname, join } from "node:path"
import { acquireLock, releaseLock } from "../../../_shared/mcp-sync-lock.ts"

const POLL_MS = 2000
const DEV_BOT_ROOT = join(import.meta.dir, "../../../..")

export default Plugin.define({
  id: "devbot-mcp-sync",
  async setup(ctx: any) {
    const root: string = ctx.location?.project?.canonical || ctx.location?.directory || process.cwd()
    const config = join(root, "opencode.jsonc")
    const helper = join(DEV_BOT_ROOT, "src", "harnesses", "opencode-v2", "lib", "v2config.py")
    const logFile = join(root, ".agents", "logs", "mcp-sync.log")

    let previous = ""
    let busy = false

    const log = (line: string) => {
      try {
        mkdirSync(dirname(logFile), { recursive: true })
        appendFileSync(logFile, `${new Date().toISOString()} [mcp-sync] ${line}\n`)
      } catch {
        // Logging must never break the harness.
      }
    }

    const serversFrom = (out: any): any[] => {
      if (Array.isArray(out)) return out
      if (Array.isArray(out?.servers)) return out.servers
      if (Array.isArray(out?.data?.servers)) return out.data.servers
      return []
    }

    async function tick() {
      if (busy) return
      busy = true
      try {
        const servers = serversFrom(await ctx.mcp.list())
        if (servers.length === 0) return

        const signature = servers
          .map((s) => `${s?.name}=${s?.status?.status ?? s?.status ?? ""}`)
          .sort()
          .join(",")
        if (signature === previous) return

        // Only forget the old signature once every write landed; otherwise the
        // next tick must retry the ones that did not.
        let failed = false
        for (const server of servers) {
          const name = String(server?.name ?? "")
          if (!name) continue
          const disabled = (server?.status?.status ?? server?.status) === "disabled"
          // Two sessions (or a reinit) rewrite the same file; without the
          // lock one update is lost, so re-check on the next tick instead.
          const locked = `${config}.mcp-sync.lock`
          const token = acquireLock(locked)
          if (!token) {
            log(`${name}: locked by another session — retrying`)
            failed = true
            continue
          }
          try {
            const proc = Bun.spawn(
              ["python3", helper, "set-mcp-disabled", config, name, String(disabled)],
              { cwd: root, stdout: "pipe", stderr: "pipe" },
            )
            const exitCode = await proc.exited
            if (exitCode === 0) {
              log(`wrote ${name}: disabled=${disabled}`)
            } else {
              failed = true
            }
          } finally {
            releaseLock(locked, token)
          }
        }
        if (!failed) previous = signature
      } catch (e) {
        log(`WARN: ${e instanceof Error ? e.message : String(e)}`)
      } finally {
        busy = false
      }
    }

    const timer = setInterval(() => void tick(), POLL_MS)
    void tick()
    return () => clearInterval(timer)
  },
})
