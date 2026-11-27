// src/harnesses/opencode-v2/hooks/agent-communication-herdr/index.ts
// A v2 host runs no V1 plugin hooks, so the module's idle
// pass is wrapped here against a v2 context.

import { Plugin } from "@opencode/plugin"
import { join } from "node:path"
import { createLogger } from "../../../../_shared/logger.ts"
import { defaultHookLog, disabledModules } from "../../on-hooks-utils"
import { makeOnSessionIdleValidate } from "../../../../agentic/agent-communication/hooks/opencode/on-session-idle-validate"
import { DEV_BOT_ROOT, forEachIdle, v2Client } from "./lib"

export default Plugin.define({
  id: "devbot-agent-communication-herdr",
  async setup(ctx: any) {
    const root: string = ctx.location?.project?.canonical || ctx.location?.directory || process.cwd()
    if (disabledModules(root, DEV_BOT_ROOT).has("agent-communication")) return

    const log = createLogger({
      module: "agent-communication",
      logFile: join(root, defaultHookLog()),
    })
    const hooks: any = await makeOnSessionIdleValidate({ log })({
      directory: ctx.location?.directory ?? root,
      worktree: root,
      client: v2Client(ctx),
    })

    const controller = new AbortController()
    void (async () => {
      try {
        await forEachIdle(
          ctx,
          async (event) => {
            try {
              await hooks.event({ event })
            } catch (e) {
              log.warn(`session.idle failed: ${e instanceof Error ? e.message : String(e)}`)
            }
          },
          controller.signal,
        )
      } catch (e) {
        if (!controller.signal.aborted) {
          log.error(`event subscription ended: ${e instanceof Error ? e.message : String(e)}`)
        }
      }
    })()
    return () => controller.abort()
  },
})
