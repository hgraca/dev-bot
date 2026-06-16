import type { Plugin } from "@opencode-ai/plugin"
import path from "path"
import { createLogger } from "../../../../_shared/logger.ts"

export const OnFileEditedFormatYml: Plugin = async ({ project, $, client }) => {
  const logger = createLogger({ module: "format-yml" })
  return {
    event: async ({ event }) => {
      if (event.type !== "file.edited") return
      const file: string = (event as any).properties?.file ?? ""
      if (!file.endsWith(".yml") && !file.endsWith(".yaml")) return
      const py = path.join(import.meta.dir, "../../tools/format-yml.py")
      try {
        await $`python3 ${py} ${file}`.cwd(project.worktree).quiet()
      } catch (e) { logger.info(`format-yml hook failed for ${file}: ${e instanceof Error ? e.message : String(e)}`) }
    },
  }
}
