// =============================================================================
// src/harnesses/opencode-v2/hooks/pty/lib.ts
// Pure logic for the PTY extension: the session-info shape, the sidebar rows,
// the panel's text, and the read pagination.
//
// No host API and no I/O, so both halves can use it and a test can drive it: the
// server part builds session info through it, the TUI part renders through it,
// and the v1 monitor put the same guarantee in its own lib after finding that
// every bug lived in one of these functions.
// =============================================================================

import type { PtySessionInfo, PtyStatus } from "./rpc"

/** What the registry stores about a session, minus its process handle. */
export interface PtyRecord {
  id: string
  title: string
  command: string
  workdir: string
  pid: number
  parentSessionId: string
  /** Epoch milliseconds. */
  createdAt: number
  /** Epoch milliseconds, null while the child runs. */
  exitAt: number | null
  exitCode: number | null
  /** Set when the session was stopped on request, so the panel can say so. */
  killed: boolean
  lineCount: number
}

/** `killed` outranks the exit code: a session we stopped did not fail. */
export function statusOf(record: Pick<PtyRecord, "exitAt" | "killed">): PtyStatus {
  if (record.exitAt === null) return "running"
  return record.killed ? "killed" : "exited"
}

/** The published shape: epoch milliseconds become ISO, and the derived status
 *  replaces the internal flags. */
export function sessionInfo(record: PtyRecord): PtySessionInfo {
  return {
    id: record.id,
    title: record.title,
    command: record.command,
    workdir: record.workdir,
    status: statusOf(record),
    pid: record.pid,
    exitCode: record.exitCode,
    exitAt: record.exitAt === null ? null : new Date(record.exitAt).toISOString(),
    createdAt: new Date(record.createdAt).toISOString(),
    lineCount: record.lineCount,
    parentSessionId: record.parentSessionId,
  }
}

/** The sessions a given agent session spawned, in list order. */
export function filterByParent<T extends { parentSessionId: string }>(
  list: readonly T[],
  parentSessionId: string,
): T[] {
  if (!parentSessionId) return [...list]
  return list.filter((session) => session.parentSessionId === parentSessionId)
}

/** The sessions spawned anywhere in one session's family, in list order.
 *
 *  A PTY spawned by a subagent carries the subagent's id, never the root's, so
 *  filtering on the id alone would hide the most common case in this repo. The
 *  caller passes the session in view plus `ctx.data.session.family(...)` — the
 *  host's own list of descendant sessions. */
export function filterByFamily<T extends { parentSessionId: string }>(
  list: readonly T[],
  family: readonly string[],
): T[] {
  const owned = new Set(family.filter((id) => typeof id === "string" && id.length > 0))
  if (owned.size === 0) return []
  return list.filter((session) => owned.has(session.parentSessionId))
}

/** The session whose output a panel shows for a viewer, or "" when the panel
 *  was opened without a row having been picked. */
export function selectedSession(
  selected: Readonly<Record<string, string>>,
  viewerSessionId: string | undefined,
): string {
  if (!viewerSessionId) return ""
  return selected[viewerSessionId] ?? ""
}

/** A viewer's selection after a row was opened. Kept apart from the render path
 *  so the sidebar's hand-off to the panel is a tested decision: each agent
 *  session remembers its own row, and opening one never clears another's. */
export function selectSession(
  selected: Readonly<Record<string, string>>,
  viewerSessionId: string,
  sessionId: string,
): Record<string, string> {
  if (!viewerSessionId) return { ...selected }
  return { ...selected, [viewerSessionId]: sessionId }
}

/** The spawning agent session carried by a tool call.
 *
 *  Extracted so the mapping the info shape depends on is a tested one-liner
 *  rather than an expression buried in a tool executor. */
export function parentSessionIdOf(context: unknown): string {
  const sessionID = (context as { sessionID?: unknown } | null | undefined)?.sessionID
  return typeof sessionID === "string" ? sessionID : ""
}

/** Title column width in the sidebar. */
const TITLE_MAX = 24

function truncate(value: string, max: number): string {
  if (value.length <= max) return value
  return value.slice(0, max - 1) + "\u2026"
}

/** The trailing state field of a row: live line count, exit code, or status. */
function rowTail(info: PtySessionInfo): string {
  if (info.status === "running") return `${info.lineCount}L`
  if (typeof info.exitCode === "number") return `exit ${info.exitCode}`
  return info.status
}

/** `<title or command>  <state>`, truncated to the sidebar's title column. */
export function rowLabel(info: PtySessionInfo): string {
  const title = info.title || info.command || "untitled"
  return `${truncate(title, TITLE_MAX)}  ${rowTail(info)}`
}

/** Which theme colour a row's bullet should take. A semantic key, not a colour,
 *  so it stays pure — the palette lookup belongs to the caller. */
export function rowTone(info: PtySessionInfo): "success" | "error" | "muted" {
  if (info.status === "running") return "success"
  if (typeof info.exitCode === "number" && info.exitCode !== 0) return "error"
  return "muted"
}

/** Whether a session has stopped. Only a running session is live, so anything
 *  else is a record that can be dropped without killing a process. */
export function isFinished(info: Pick<PtySessionInfo, "status">): boolean {
  return info.status !== "running"
}

/** The sessions a "clear finished" acts on, kept in their list order. */
export function finishedSessions(list: readonly PtySessionInfo[]): PtySessionInfo[] {
  return list.filter(isFinished)
}

/** The header's clear-action label, or null when there is nothing to clear.
 *
 *  Null rather than a disabled label: a control that would delete nothing
 *  should not be offered, and can never read as touching a live session. */
export function clearActionLabel(list: readonly PtySessionInfo[]): string | null {
  return finishedSessions(list).length > 0 ? "(clear finished)" : null
}

/** Removing a RUNNING session kills a live process, so it is confirmed first; a
 *  finished one is only a record, so its row acts at once. */
export function needsConfirm(info: Pick<PtySessionInfo, "status">): boolean {
  return !isFinished(info)
}

/** The selection after a session was removed: the viewer forgets it when it was
 *  the row the panel was showing, and keeps any other. */
export function dropSelection(
  selected: Readonly<Record<string, string>>,
  viewerSessionId: string | undefined,
  removedId: string,
): Record<string, string> {
  if (!viewerSessionId) return { ...selected }
  if (selected[viewerSessionId] !== removedId) return { ...selected }
  const next = { ...selected }
  delete next[viewerSessionId]
  return next
}

/** The block's header: how many sessions, and how many are still live. */
export function headerLabel(input: { count: number; running: number }): string {
  if (input.count === 0) return "PTY"
  if (input.running === input.count) return `PTY ${input.count} running`
  return `PTY ${input.count}`
}

/** The panel's header: the detail that does not fit a sidebar row.
 *
 *  Capped at TWO lines on purpose: every line spent here is a line unavailable
 *  to the output. */
export function formatDetail(info: PtySessionInfo): string {
  const head = [
    info.id,
    info.status,
    `pid ${info.pid}`,
    `${info.lineCount} lines`,
  ].join("  ")
  const body = [info.command, info.workdir].filter(Boolean).join("  \u00b7  ")
  return body ? `${head}\n${body}` : head
}

/** How long a session has been running, as a compact label.
 *
 *  Seconds zero-padded below an hour, minutes above it; a session with no usable
 *  start time shows nothing rather than a wrong number. */
export function formatDuration(ms: number): string {
  const totalSeconds = Number.isFinite(ms) && ms > 0 ? Math.floor(ms / 1000) : 0
  const seconds = totalSeconds % 60
  const minutes = Math.floor(totalSeconds / 60) % 60
  const hours = Math.floor(totalSeconds / 3600)
  if (hours > 0) return `${hours}h ${String(minutes).padStart(2, "0")}m`
  if (minutes > 0) return `${minutes}m ${String(seconds).padStart(2, "0")}s`
  return `${seconds}s`
}

/** Elapsed time from spawn to exit, or to `now` while the child runs. */
export function runDurationMs(
  info: Pick<PtySessionInfo, "createdAt" | "exitAt">,
  now: number,
): number | null {
  const started = Date.parse(info.createdAt)
  if (!Number.isFinite(started)) return null
  const ended = info.exitAt === null ? now : Date.parse(info.exitAt)
  if (!Number.isFinite(ended)) return null
  return Math.max(0, ended - started)
}

/** The last `limit` entries, prefixed with `…` when anything was cut: the panel
 *  shows the newest output, and an off-by-one here would silently hide it. */
export function tailLines(lines: readonly string[], limit: number): string[] {
  if (limit <= 0 || lines.length <= limit) return [...lines]
  return ["\u2026", ...lines.slice(lines.length - limit)]
}

/** One page of buffer lines, optionally filtered by a regular expression.
 *
 *  The pattern filters first and the offset then applies to the matches, which
 *  is what makes `pty_read pattern=error` return early errors instead of the
 *  first page of unfiltered output. */
export function pageLines(
  lines: readonly string[],
  input: { offset?: number; limit?: number; pattern?: string },
): { ok: true; lines: string[]; total: number } | { ok: false; error: string } {
  let matched: readonly string[] = lines
  if (input.pattern) {
    let re: RegExp
    try {
      re = new RegExp(input.pattern)
    } catch (e) {
      return { ok: false, error: `invalid pattern: ${e instanceof Error ? e.message : String(e)}` }
    }
    matched = lines.filter((line) => re.test(line))
  }
  const offset = Math.max(0, Number(input.offset ?? 0))
  const limit = Math.max(1, Number(input.limit ?? 200))
  return { ok: true, lines: matched.slice(offset, offset + limit), total: matched.length }
}
