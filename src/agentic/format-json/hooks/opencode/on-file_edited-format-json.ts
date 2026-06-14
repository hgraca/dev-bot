import type { Plugin } from "@opencode-ai/plugin"
import path from "path"
import { createLogger } from "../../../../_shared/logger.ts"

export const OnFileEditedFormatJson: Plugin = async ({ project, $, client }) => {
  const logger = createLogger({ module: "format-json" })
  return {
    event: async ({ event }) => {
      if (event.type !== "file.edited") return
      const file: string = (event as any).properties?.file ?? ""
      if (!file.endsWith(".json") && !file.endsWith(".jsonc")) return
      const py = path.join(import.meta.dir, "../../tools/format-json.py")
      try {
        await $`python3 ${py} ${file}`.cwd(project.worktree).quiet()
      } catch (e) { logger.info(`format-json hook failed for ${file}: ${e instanceof Error ? e.message : String(e)}`) }
    },
  }
}
