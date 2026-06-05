import type { Plugin } from "@opencode-ai/plugin"
import path from "path"
import { createLogger } from "../../../../_shared/logger.ts"

export const OnFileEditedReindexPassiveMemories: Plugin = async ({ project, client }) => {
  const logger = createLogger({ module: "memory" })
  return {
    event: async ({ event }) => {
      if (event.type !== "file.edited") return
      const file: string = (event as any).properties?.file ?? ""
      if (!file.endsWith(".md")) return
      // Only react to passive memory paths: latent/global/ or latent/learnings/
      if (!file.includes("/memory/latent/global") && !file.includes("/memory/latent/learnings")) return
      try {
        const logsDir = path.join(project.worktree, ".agents", "logs")
        const logFile = path.join(logsDir, "qmd-index.log")
        const iso = new Date().toISOString()
        const proc = Bun.spawn(
          ["bash", "-c", `mkdir -p "${logsDir}" && printf '[%s] [QMD-INDEX] file=%s cmd="qmd update && qmd embed"\\n' "${iso}" "${file}" >> "${logFile}" && qmd update && qmd embed >> "${logFile}" 2>&1`],
          { cwd: project.worktree, stdio: ["ignore", "ignore", "ignore"], detached: true },
        )
        proc.unref()
      } catch (e) { logger.info(`reindex-passive-memories hook failed: ${e instanceof Error ? e.message : String(e)}`) }
    },
  }
}
