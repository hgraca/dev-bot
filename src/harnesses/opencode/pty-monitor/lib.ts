// =============================================================================
// src/harnesses/opencode/pty-monitor/lib.ts
// Pure logic for the PTY monitor TUI plugin — no TUI, no I/O, no host API.
//
// Kept deliberately separate from the wiring so it can be unit-tested: the TUI
// half cannot be driven headlessly, but every bug found while spiking this
// feature lived in one of these functions.
//
// TypeScript here is type-only (no runtime syntax beyond what bun strips).
// =============================================================================

/** Matches the PTY web interface URL that opencode-pty posts into the session.
 *  A scheme is REQUIRED: the earlier loose `\S+` form matched a doc placeholder
 *  ("PTY Sessions Web Interface URL: `<url>`.") that appears in the transcript,
 *  producing "fetch() URL is invalid". */
const URL_RE = /PTY Sessions Web Interface URL:\s*(https?:\/\/\S+)/g

/** Trailing punctuation that can follow a URL in prose but is not part of it. */
const TRAILING_JUNK = /[.,;:`'")\]]+$/

/**
 * Extract the newest origin found in a single text, or null.
 *
 * Newest within the text, not first, because the PTY server binds a fresh
 * random port on every start — an earlier mention is a dead port.
 */
export function matchServerUrl(text: unknown): string | null {
  if (typeof text !== "string" || text.length === 0) return null
  const re = new RegExp(URL_RE.source, "g")
  let match: RegExpExecArray | null
  let found: string | null = null
  while ((match = re.exec(text)) !== null) {
    found = match[1].replace(TRAILING_JUNK, "")
  }
  return found
}

/**
 * Extract the newest origin across an ordered list of texts (oldest first), or
 * null. This is the function the plugin actually uses: it maps the session's
 * message texts through here and takes the result as the live origin.
 */
export function latestServerUrl(texts: unknown): string | null {
  if (!Array.isArray(texts)) return null
  let found: string | null = null
  for (const text of texts) {
    const hit = matchServerUrl(text)
    if (hit) found = hit
  }
  return found
}

/**
 * The error opencode-pty's command handler throws to signal it handled the
 * command itself.
 *
 * It is NOT a failure: the handler throws only after it has already started the
 * PTY server and posted the URL, using the throw to stop opencode running the
 * command's template. Reading it as an error is what made a working server look
 * unavailable.
 */
export const PTY_COMMAND_SENTINEL = "Command handled by PTY plugin"

export function isPtyCommandSentinel(error: unknown): boolean {
  const message =
    error && typeof error === "object" && "message" in error
      ? String((error as { message: unknown }).message)
      : String(error)
  return message.includes(PTY_COMMAND_SENTINEL)
}

/**
 * The message worth remembering as the bootstrap's failure cause, or null when
 * there is nothing to report.
 *
 * The sentinel is not a failure — opencode-pty throws it only after it has
 * started the server and posted the URL — so recording it would report a
 * working server as unavailable.
 */
export function bootstrapFailureCause(error: unknown): string | null {
  if (isPtyCommandSentinel(error)) return null
  return String(error)
}

/**
 * Decode a `/api/sessions/:id/buffer/plain` response into displayable text.
 *
 * The endpoint returns a JSON envelope — `{ plain, byteLength }` — not a raw
 * body, and the content is CRLF-terminated (it is a terminal buffer).
 */
export function decodeBuffer(raw: unknown): string {
  let text: string
  if (typeof raw === "string") {
    text = raw
  } else if (raw && typeof raw === "object" && typeof (raw as { plain?: unknown }).plain === "string") {
    text = (raw as { plain: string }).plain
  } else {
    return ""
  }
  return text.replace(/\r\n/g, "\n")
}

/** Title column width in the sidebar. */
const TITLE_MAX = 24

function truncate(value: string, max: number): string {
  if (value.length <= max) return value
  return value.slice(0, max - 1) + "…"
}

/** Every row carries the same bullet, matching the built-in sidebar items
 *  (MCP, File Tree, Todo); the colour carries the state instead. */
export const ROW_BULLET = "• "

/**
 * A row's text WITHOUT its bullet, so the caller can colour the bullet
 * separately — the built-in sidebar items style the glyph and leave the label in
 * the normal text colour.
 */
/**
 * The trailing state field of a row.
 *
 * opencode-pty's status is not just running/exited — it also reports `killing`
 * and `killed`, which carry no exit code. Rendering those as `exit ?` reads as a
 * bug, so any non-running state without a numeric exit code shows the status
 * word itself.
 */
function rowTail(s: { status?: unknown; lineCount?: unknown; exitCode?: unknown }): string {
  if (s.status === "running") {
    return `${typeof s.lineCount === "number" ? s.lineCount : 0}L`
  }
  if (typeof s.exitCode === "number") return `exit ${s.exitCode}`
  return typeof s.status === "string" && s.status.length > 0 ? s.status : "?"
}

export function rowLabel(session: unknown): string {
  const s = (session && typeof session === "object" ? session : {}) as {
    title?: unknown
    status?: unknown
    lineCount?: unknown
    exitCode?: unknown
  }
  const title = typeof s.title === "string" && s.title.length > 0 ? s.title : "untitled"
  return `${truncate(title, TITLE_MAX)}  ${rowTail(s)}`
}

/**
 * Which theme colour a row's bullet should take.
 *
 * Returns a semantic key rather than a colour so it stays pure and testable —
 * the palette lookup belongs to the caller, which has the theme.
 */
export function rowTone(session: unknown): "success" | "error" | "muted" {
  if (!session || typeof session !== "object") return "muted"
  const s = session as { status?: unknown; exitCode?: unknown }
  if (s.status === "running") return "success"
  if (typeof s.exitCode === "number" && s.exitCode !== 0) return "error"
  return "muted"
}

/**
 * Whether a session has stopped.
 *
 * `killing` is deliberately NOT finished: it is the transient state between the
 * kill request and the exit callback that reports `killed`, so treating it as
 * finished would let a clear race the process teardown.
 */
export function isFinished(session: unknown): boolean {
  if (!session || typeof session !== "object") return false
  const status = (session as { status?: unknown }).status
  return status === "exited" || status === "killed"
}

/** The sessions a "clear finished" acts on, kept in their list order. */
export function finishedSessions(list: unknown): Array<Record<string, unknown>> {
  if (!Array.isArray(list)) return []
  return list.filter(isFinished) as Array<Record<string, unknown>>
}

/**
 * The header's clear-action label, or null when there is nothing to clear.
 *
 * Returns null rather than a disabled label so the header never offers a control
 * that would delete nothing — and so it can never read as touching live sessions.
 */
export function clearActionLabel(list: unknown): string | null {
  return finishedSessions(list).length > 0 ? "(clear finished)" : null
}

/** The collapsible header's text: chevron, panel name, status. */
export function headerLabel(input: { collapsed?: unknown; status?: unknown }): string {
  const chevron = input?.collapsed ? "\u25B6" : "\u25BC"
  const status = typeof input?.status === "string" ? input.status : ""
  return `${chevron} PTY  ${status}`
}

/** Header block for the output dialog — the detail that does not fit a row.
 *
 *  Capped at TWO lines on purpose: every line spent here is a line unavailable
 *  to the output, and a taller header pushes the dialog past the screen bottom.
 */
export function formatDetail(session: unknown): string {
  if (!session || typeof session !== "object") return ""
  const s = session as {
    id?: unknown
    status?: unknown
    pid?: unknown
    lineCount?: unknown
    command?: unknown
    args?: unknown
    workdir?: unknown
  }
  const args = Array.isArray(s.args) ? s.args.filter((a) => typeof a === "string") : []
  const command = [typeof s.command === "string" ? s.command : "", ...args].filter(Boolean).join(" ")
  return [
    `${typeof s.id === "string" ? s.id : "?"}  ${typeof s.status === "string" ? s.status : "?"}  pid ${
      typeof s.pid === "number" ? s.pid : "?"
    }  lines ${typeof s.lineCount === "number" ? s.lineCount : 0}`,
    [command, typeof s.workdir === "string" ? s.workdir : ""].filter(Boolean).join("  ·  "),
  ]
    .filter((line) => line.length > 0)
    .join("\n")
}

/**
 * Ports THIS process is listening on, parsed from the /proc net tables.
 *
 * - `procTcp6` / `procTcp`: raw text of `/proc/self/net/tcp6` and
 *   `/proc/self/net/tcp`
 * - `ownInodes`: socket inode strings owned by this process, taken from the
 *   `socket:[<inode>]` targets under `/proc/self/fd`
 *
 * Exists because opencode-pty binds a RANDOM port and publishes it only by
 * posting a message into the session — reading the port from the OS avoids that
 * transcript noise entirely. Linux-only; callers fall back to the scrape
 * elsewhere.
 */
export function parseListeningPorts(
  procTcp6: unknown,
  procTcp: unknown,
  ownInodes: unknown,
): number[] {
  const owned = ownInodes instanceof Set ? (ownInodes as Set<string>) : new Set<string>()
  const ports: number[] = []
  for (const table of [procTcp6, procTcp]) {
    if (typeof table !== "string" || table.length === 0) continue
    const lines = table.split("\n")
    // Row 0 is the column header.
    for (let i = 1; i < lines.length; i++) {
      const cols = lines[i].trim().split(/\s+/)
      if (cols.length < 10) continue
      if (cols[3] !== "0A") continue // 0A = LISTEN; ignore established sockets
      if (!owned.has(cols[9])) continue // another process's socket
      const local = cols[1]
      const colon = local.lastIndexOf(":")
      if (colon < 0) continue
      const port = parseInt(local.slice(colon + 1), 16)
      if (Number.isFinite(port) && port > 0 && !ports.includes(port)) ports.push(port)
    }
  }
  return ports
}

/**
 * Does this look like opencode-pty's `/health` payload?
 *
 * Needed to pick its port out of the process's listeners, because another local
 * service can answer on a loopback port too — CUPS owns `[::1]:631` on the
 * machine this was built on and returns an HTML error page.
 */
export function isPtyHealth(value: unknown): boolean {
  if (!value || typeof value !== "object") return false
  const v = value as { status?: unknown; sessions?: unknown }
  return v.status === "healthy" && !!v.sessions && typeof v.sessions === "object"
}

/**
 * The last `lines` lines of `text`, prefixed with `…` when anything was cut.
 *
 * Lives here rather than in the plugin so it can be tested: it decides what the
 * dialog shows, and an off-by-one would silently hide the newest output.
 */
export function tail(text: unknown, lines: number): string {
  const all = String(text).split("\n")
  if (all.length <= lines) return all.join("\n")
  return "…\n" + all.slice(-lines).join("\n")
}
