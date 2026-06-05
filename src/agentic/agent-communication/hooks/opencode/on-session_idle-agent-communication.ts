// agent-communication opencode hook
// Thin wrapper — fires on session.idle and delegates all logic to
// tools/agent-communication.js (the source of truth).
//
// Marker list authority: tools/agent-communication-helpers.js
//   [FINISHED]  |  [BLOCKED]  |  [NEEDS_INPUT]  |  [PARTIAL]

import { AgentCommunicationPlugin } from "../../tools/agent-communication.js"

// ─── Plugin factory ──────────────────────────────────────────────────────────
// Exported as default so opencode's plugin loader can find it.
// Only export: opencode loader iterates Object.values(mod) and throws
// "Plugin export is not a function" for any non-function export value.

export default async function agentCommunicationPlugin({
  directory,
  worktree,
  client,
}: {
  directory: string
  worktree?: string
  client: any
}): Promise<{ event: (args: { event: any }) => Promise<void> }> {
  return AgentCommunicationPlugin({ directory, worktree, client })
}
