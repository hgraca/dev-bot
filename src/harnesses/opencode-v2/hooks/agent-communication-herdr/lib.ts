// src/harnesses/opencode-v2/hooks/agent-communication-herdr/lib.ts
// v2 speaks different shapes from the v1 side this
// adapter feeds; these normalise them.

import { join } from "node:path"

/** The repository root, five levels above this package. */
export const DEV_BOT_ROOT = join(import.meta.dir, "../../../../..")

/** A v2 event as the v1-shaped event the idle pass reads. */
export function idleEvent(event: any): any {
  const data = event?.data ?? event?.properties ?? {}
  const sessionID = data.sessionID || data.info?.id || data.id || ""
  return { type: "session.idle", properties: { ...data, sessionID } }
}

/** The entries of a client response, which wraps them in `data`. */
export function responseEntries(response: any): any[] {
  if (Array.isArray(response)) return response
  const data = response?.data
  return Array.isArray(data) ? data : []
}

/** A v2 context entry as the v1-shaped message the validator reads. */
export function messageFromEntry(entry: any): any {
  // The client already answers in message shape on some hosts.
  if (entry?.info && Array.isArray(entry?.parts)) return entry
  return {
    info: {
      role: String(entry?.type ?? ""),
      id: String(entry?.id ?? ""),
      parentID: entry?.parentID,
    },
    parts: Array.isArray(entry?.content) ? entry.content : [],
  }
}

/** The idle pass's client face, backed by a v2 plugin context. */
export function v2Client(ctx: any) {
  return {
    session: {
      messages: async ({ path }: any) => {
        const response = await ctx.session.context({ sessionID: path.id })
        return { data: responseEntries(response).map(messageFromEntry) }
      },
      get: async ({ path }: any) => ({ data: await ctx.session.get({ sessionID: path.id }) }),
    },
  }
}

/** Feed normalised idle events from a v2 event stream. */
export async function forEachIdle(
  ctx: any,
  onIdle: (event: any) => Promise<void>,
  signal?: AbortSignal,
): Promise<void> {
  // A host may ignore a type filter, so the type is checked here too.
  for await (const event of ctx.event.subscribe({ signal })) {
    if (event?.type !== "session.idle") continue
    await onIdle(idleEvent(event))
  }
}
