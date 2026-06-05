// on-session_created-graphify-update.ts
// Fires on session start — runs graphify update in background to ensure
// the knowledge graph is current before work begins.
//
// Thin trigger — all logic delegated to tools/graphify-update-bg.sh.

import type { Plugin } from "@opencode-ai/plugin"
import path from "path"

export const OnSessionCreatedGraphifyUpdate: Plugin = async ({ project }) => {
  return {
    event: async ({ event }) => {
      if (event.type !== "session.created") return

      const tool = path.join(import.meta.dir, "../../tools/graphify-update-bg.sh")
      try {
        const proc = Bun.spawn(["bash", tool, project.worktree], {
          cwd: project.worktree,
          stdio: ["ignore", "ignore", "ignore"],
          detached: true,
        })
        proc.unref()
      } catch {
        // Graceful degradation — never throw from hook
      }
    },
  }
}
