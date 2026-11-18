// Wraps the native skill tool: a display name in
// input.id is rewritten to a registered skill id.

import { Plugin } from "@opencode/plugin"
import { join } from "node:path"
import { createLogger } from "../../../_shared/logger.ts"
import { defaultHookLog } from "../on-hooks-utils"
import { resolveSkillInput } from "../skill-name-resolver-utils"

export default Plugin.define({
  id: "devbot-skill-name-resolver",
  async setup(ctx: any) {
    const root: string = ctx.location?.project?.canonical || ctx.location?.directory || process.cwd()
    const log = createLogger({ module: "skill-name-resolver", logFile: join(root, defaultHookLog()) })

    await ctx.tool.hook("execute.before", async (event: any) => {
      if (String(event?.tool ?? "").toLowerCase() !== "skill") return
      await resolveSkillInput(event?.input, { list: () => ctx.skill.list(), log })
    })
  },
})
