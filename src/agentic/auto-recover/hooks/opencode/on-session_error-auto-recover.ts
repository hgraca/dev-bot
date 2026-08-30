import type { Plugin } from "@opencode-ai/plugin"
import { join } from "path"
import { createLogger } from "../../../../_shared/logger.ts"
import { checkAndAcquire, releaseLock } from "../../tools/auto-recover.ts"

export const OnSessionErrorAutoRecover: Plugin = async ({ directory, worktree, client }) => {
  const root = worktree || directory
  const logger = createLogger({
    client,
    module: "auto-recover",
    // audit-24 NOTE-2: capture logger output in the hooks log file.
    logFile: join(root, ".agents/logs/hooks.log"),
  })
  return {
    event: async ({ event }: { event: any }) => {
      if (event.type !== "session.error") return

      const sessionId =
        event?.properties?.sessionID || event?.properties?.info?.id || event?.properties?.id
      if (!sessionId) return

      const errMsg: string =
        event?.properties?.error?.message ||
        event?.properties?.error?.data?.message ||
        event?.properties?.message ||
        ""

      const result = checkAndAcquire(sessionId, errMsg, root)
      if (!result.recover) return

      try {
        await new Promise((r) => setTimeout(r, 1500))
        await client.session.prompt({
          path: { id: sessionId },
          body: {
            parts: [
              {
                type: "text",
                text: result.recoveryText,
                synthetic: true,
                metadata: {
                  hidden: true,
                  source: "auto-recover-plugin",
                  attempt: result.attempt,
                  maxAttempts: result.maxAttempts,
                  errorPreview: result.errorPreview,
                },
              },
            ],
          },
        })
      } catch (e) {
        logger.error(`auto-recover prompt injection failed: ${e instanceof Error ? e.message : String(e)}`)
      }

      releaseLock(root)
    },
  }
}

export default OnSessionErrorAutoRecover
