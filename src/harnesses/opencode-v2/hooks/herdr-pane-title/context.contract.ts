// Typecheck-only: the host keeps the members and
// event fields the plugin reads.

import type { Plugin } from "@opencode/plugin/tui"
import type { TuiCtx } from "./tui"

export const hostContextFits = (ctx: Plugin.Context): TuiCtx => ctx

// `session` is optional in the slice, so this check
// pins its presence on the host.
export const hostSessionFits = (ctx: Plugin.Context) => ctx.data.session

// Every field the plugin reads must exist on the
// host's event payload.
export const eventFieldsFit = (ctx: Plugin.Context) => {
  const created = ctx.data.on("session.created", (event) =>
    [event.data.sessionID, event.data.parentID, event.data.title] as const,
  )
  const renamed = ctx.data.on("session.renamed", (event) => [event.data.sessionID, event.data.title] as const)
  const deleted = ctx.data.on("session.deleted", (event) => [event.data.sessionID] as const)
  return { created, renamed, deleted }
}
