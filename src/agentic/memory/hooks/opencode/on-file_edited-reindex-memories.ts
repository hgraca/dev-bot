import type { Plugin } from "@opencode-ai/plugin"
import path from "path"
import { createLogger } from "../../../../_shared/logger.ts"

export const OnFileEditedReindexMemories: Plugin = async ({ project, client }) => {
  const logger = createLogger({ module: "memory" })
  return {
    event: async ({ event }) => {
      if (event.type !== "file.edited") return
      const file: string = (event as any).properties?.file ?? ""
      if (!file.endsWith(".md")) return
      if (!file.includes("/memory/latent")) return
      const tool = path.join(import.meta.dir, "../../tools/reindex-memories/reindex-memories.sh")
      try {
        const proc = Bun.spawn(["bash", tool], { cwd: project.worktree, stdio: ["ignore", "ignore", "ignore"], detached: true })
        proc.unref()
      } catch (e) { logger.info(`reindex-memories hook failed: ${e instanceof Error ? e.message : String(e)}`) }
    },
  }
}
