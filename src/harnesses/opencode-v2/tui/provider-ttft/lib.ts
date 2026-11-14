// Type-only TS: bun strips the annotations.

/** An in-flight assistant request. */
export interface PendingRequest {
  created: number
  reported?: boolean
}

/** The assistant-message fields read here. */
export interface AssistantMessageLike {
  id?: string
  role?: string
  time?: { created?: number; completed?: number }
}

/** Track an in-flight request; a completed
 *  message without a delta leaves no entry. */
export function recordAssistantMessage(
  pending: Map<string, PendingRequest>,
  info: AssistantMessageLike | undefined,
): void {
  if (!info || info.role !== "assistant") return
  if (typeof info.id !== "string") return
  // A re-emitted update must not re-arm a
  // request that already reported its first token.
  if (!pending.has(info.id) && typeof info.time?.created === "number") {
    pending.set(info.id, { created: info.time.created })
  }
  if (info.time?.completed) pending.delete(info.id)
}

/** Time to first token for the first delta;
 *  `undefined` otherwise. The first is final. */
export function takeFirstDelta(
  pending: Map<string, PendingRequest>,
  messageID: string,
  now: number,
): number | undefined {
  const entry = pending.get(messageID)
  if (!entry || entry.reported) return undefined
  const elapsed = now - entry.created
  if (elapsed < 0) return undefined
  entry.reported = true
  return elapsed
}

/** Per-session copy with this value, capped at
 *  `limit`; the oldest session is evicted. */
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
export function formatTtft(ms: number): string {
  return (ms / 1000).toFixed(1) + "s"
}
