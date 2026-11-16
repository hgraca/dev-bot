// src/harnesses/opencode-v2/tui/provider-ttft/lib.ts
// Time-to-first-token bookkeeping for the sidebar row.
//
// v2 records both stamps on the assistant message itself (`time.created` and
// `time.firstToken`), so the plugin reads them instead of timing raw deltas as
// the v1 part had to.

/** The assistant-message fields read here. */
export interface AssistantLike {
  id?: string
  type?: string
  role?: string
  time?: { created?: number; firstToken?: number }
}

/**
 * Milliseconds from request start to the first streamed token, or `undefined`
 * when the host has not recorded both stamps yet.
 */
export function firstTokenMs(info: AssistantLike | undefined): number | undefined {
  if (!info) return undefined
  // One field is `type` in v2 and `role` in v1; the plugin runs on v2 only, and
  // accepting either keeps the helper honest about what it reads.
  if (info.type !== undefined && info.type !== "assistant") return undefined
  if (info.type === undefined && info.role !== "assistant") return undefined
  const created = info.time?.created
  const firstToken = info.time?.firstToken
  if (typeof created !== "number" || typeof firstToken !== "number") return undefined
  const elapsed = firstToken - created
  if (elapsed < 0) return undefined
  return elapsed
}

/** Per-session copy with this value, capped at `limit`; the oldest is evicted. */
export function withTtft(
  bySession: Map<string, number>,
  sessionID: string,
  ms: number,
  limit = 200,
): Map<string, number> {
  const next = new Map(bySession)
  next.delete(sessionID)
  next.set(sessionID, ms)
  if (next.size > limit) {
    const oldest = next.keys().next().value
    if (oldest !== undefined) next.delete(oldest)
  }
  return next
}

/** One compact value: `0.8s`, `1.2s`. */
export function formatTtft(ms: number | undefined): string {
  if (ms === undefined) return "-"
  return (ms / 1000).toFixed(1) + "s"
}
