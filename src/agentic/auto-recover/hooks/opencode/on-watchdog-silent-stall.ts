// src/agentic/auto-recover/hooks/opencode/on-watchdog-silent-stall.ts
// Watchdog for silently-stalled subagent sessions.
//
// Background: provider streams can hang without raising an error event
// (observed with cortecs/kimi-k3 — a vision generation stalled for 4+
// minutes emitting nothing). opencode's auto-recover only fires on
// session.error, so a silent hang is never recovered. This watchdog polls
// subagent sessions and aborts any that stay busy without activity past a
// timeout, which surfaces the failure to the parent's `task` tool so the
// orchestrator can retry.
//
// Two-strike design: the first observation of a stale busy subagent is only
// logged; the session is aborted only if it is still stale on a later check,
// so a legitimately slow-but-streaming subagent is never killed on a single
// sample.
//
// False-positive guard: a busy session can look stale while legitimately
// waiting on a long-running tool (session.time.updated does not bump while
// the tool executes). Only a pure generation stall — an in-flight assistant
// message with no pending tool call — is a candidate for abort; finished
// sessions are idle and skipped outright.
//
// Timeout config (env):
//   DEV_BOT_STALL_TIMEOUT_MS  default 900000 (15 min)
//   DEV_BOT_STALL_CHECK_MS    default 30000  (poll interval)
//
// audit-26 false positive: a subagent running a long tool call (the full
// test suite) looked "silent" because session.time.updated does not bump
// while a tool executes, and the in-flight tool part sat on an earlier
// message — the old check only inspected the last message. The timeout was
// also raised from 3 min to 15 min: a legitimate subagent running a long
// suite must never be aborted.

import type { Plugin } from "@opencode-ai/plugin"
import { join } from "path"
import { createLogger } from "../../../../_shared/logger.ts"

const STALL_MS = Number(process.env.DEV_BOT_STALL_TIMEOUT_MS || 900_000)
const CHECK_MS = Number(process.env.DEV_BOT_STALL_CHECK_MS || 30_000)

/**
 * Two-strike stall decision for a subagent first seen stale at `firstSeenAt`.
 * - "watch": first strike — log only, wait for confirmation
 * - "wait":  still within the confirmation window
 * - "abort": stale across consecutive checks — kill the session
 */
export function stallDecision(
  firstSeenAt: number | undefined,
  now: number,
  checkMs: number,
): "watch" | "wait" | "abort" {
  if (firstSeenAt === undefined) return "watch"
  return now - firstSeenAt >= checkMs ? "abort" : "wait"
}

/**
 * True when the session's last message is an assistant message still being
 * generated (no `completed` time) and is NOT waiting on a tool call. A busy
 * session whose last message is completed (turn finished, awaiting parent
 * pickup) or waiting on a pending/running tool (e.g. a long npm install) must
 * never be treated as a generation stall.
 */
export function isInFlightGeneration(last: any): boolean {
  if (!last?.info) return false
  const info = last.info
  if (info.role !== "assistant") return false
  if (info.time?.completed !== undefined) return false
  const parts: any[] = Array.isArray(last.parts) ? last.parts : []
  return !parts.some(
    (p) => p?.type === "tool" && (p?.state === "pending" || p?.state === "running"),
  )
}

/**
 * True when ANY recent message is waiting on an in-flight tool call
 * (pending/running). audit-26: while a long tool executes (e.g. the test
 * suite), the pending/running tool part can sit on an earlier message while
 * the last message is completed text or the tool result — so checking only
 * the last message misclassified a busy subagent as a generation stall.
 */
export function hasInFlightTool(messages: any[]): boolean {
  if (!Array.isArray(messages)) return false
  return messages.some((m) =>
    Array.isArray(m?.parts) &&
    m.parts.some(
      (p: any) => p?.type === "tool" && (p?.state === "pending" || p?.state === "running"),
    ),
  )
}

export const OnWatchdogSilentStall: Plugin = async ({ directory, worktree, client }) => {
  const root = worktree || directory
  const logger = createLogger({
    client,
    module: "watchdog",
    // audit-24 NOTE-2: capture logger output in the hooks log file.
    logFile: join(root, ".agents/logs/hooks.log"),
  })

  // sessionId -> epoch ms when the session was first observed stale
  const firstSeenStale = new Map<string, number>()

  async function check(): Promise<void> {
    try {
      const list = await client.session.list({ query: { directory: root } })
      const sessions: any[] = Array.isArray(list?.data) ? list.data : []
      const now = Date.now()

      for (const session of sessions) {
        // Only subagent sessions (children of a primary session).
        if (!session?.id || !session?.parentID) continue

        let status: any
        try {
          status = (await client.session.status({ path: { id: session.id } }))?.data
        } catch {
          continue // status unavailable — skip; next poll will retry
        }
        // The status endpoint returns a map keyed by session id; read both
        // shapes defensively.
        const state = status?.type ?? status?.[session.id]?.type
        if (state !== "busy") {
          firstSeenStale.delete(session.id)
          continue
        }

        const lastActivity: number = session.time?.updated ?? now
        const staleMs = now - lastActivity
        if (staleMs < STALL_MS) {
          firstSeenStale.delete(session.id)
          continue
        }

        // A busy session can look stale while waiting on a long tool call —
        // only a pure generation stall is a candidate for abort. Check ALL
        // recent messages for an in-flight tool (audit-26: the pending/running
        // part may sit on an earlier message, not the last one).
        let last: any
        let msgs: any[] = []
        try {
          const data = (await client.session.messages({ path: { id: session.id } }))?.data
          msgs = Array.isArray(data) ? data : []
          last = msgs.length > 0 ? msgs[msgs.length - 1] : undefined
        } catch {
          continue // messages unavailable — skip; next poll will retry
        }
        if (hasInFlightTool(msgs)) {
          firstSeenStale.delete(session.id)
          continue
        }
        if (!isInFlightGeneration(last)) {
          firstSeenStale.delete(session.id)
          continue
        }

        const first = firstSeenStale.get(session.id)
        const decision = stallDecision(first, now, CHECK_MS)
        if (decision === "watch") {
          firstSeenStale.set(session.id, now)
          logger.warn(
            `subagent ${session.id} (${session.title ?? "?"}) busy but silent for ` +
              `${Math.round(staleMs / 1000)}s — will abort if still silent`,
          )
          continue
        }
        if (decision === "wait") continue

        logger.error(
          `subagent ${session.id} stalled ${Math.round(staleMs / 1000)}s with no activity — aborting`,
        )
        try {
          await client.session.abort({ path: { id: session.id } })
          logger.info(`aborted stalled subagent ${session.id}`)
        } catch (e) {
          logger.error(`abort failed for ${session.id}: ${e instanceof Error ? e.message : String(e)}`)
        }
        firstSeenStale.delete(session.id)
      }
    } catch (e) {
      logger.warn(`watchdog check failed: ${e instanceof Error ? e.message : String(e)}`)
    }
  }

  // First pass shortly after startup (server may still be bootstrapping),
  // then poll on the interval. Do not keep the host process alive for us.
  const first = setTimeout(() => void check(), 5_000)
  const timer = setInterval(() => void check(), CHECK_MS)
  if (typeof (timer as any).unref === "function") (timer as any).unref()
  if (typeof (first as any).unref === "function") (first as any).unref()

  return {}
}

export default OnWatchdogSilentStall
