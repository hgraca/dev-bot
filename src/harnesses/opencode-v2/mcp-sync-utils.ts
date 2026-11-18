// src/harnesses/opencode-v2/mcp-sync-utils.ts
// Pure decisions for the runtime MCP sync. Both traps live here so they are
// testable without a running server:
//
//   - the shape `ctx.mcp.list()` returns, and
//   - "only a transition between polls is user intent".
//
// The hook itself only wires these to the host and to lib/v2config.py.

/** The status strings the host reports. */
export type McpStatus = string

/** One entry of the host's MCP list. */
export interface McpServerLike {
  name?: string
  status?: { status?: McpStatus } | McpStatus
}

/**
 * The servers in a `ctx.mcp.list()` result.
 *
 * v2 answers `{ location, data: Mcp.Server[] }`; the older wrappers are still
 * tolerated so a host that changes its envelope degrades to "no change" rather
 * than "no servers, forever" — the failure this function exists to prevent.
 */
export function serversFrom(output: unknown): McpServerLike[] {
  const out = output as any
  if (Array.isArray(out)) return out
  if (Array.isArray(out?.data)) return out.data
  if (Array.isArray(out?.servers)) return out.servers
  if (Array.isArray(out?.data?.servers)) return out.data.servers
  return []
}

/** The status string for one server, whichever shape carries it. */
export function statusOf(server: McpServerLike | undefined): McpStatus {
  if (!server) return ""
  const raw = server.status as any
  if (typeof raw === "string") return raw
  return typeof raw?.status === "string" ? raw.status : ""
}

/** Status by server name — the snapshot the next poll compares against. */
export function statusMap(servers: McpServerLike[]): Map<string, McpStatus> {
  const map = new Map<string, McpStatus>()
  for (const server of servers) {
    const name = typeof server?.name === "string" ? server.name : ""
    if (name) map.set(name, statusOf(server))
  }
  return map
}

/**
 * The config value a runtime status implies, or `null` when it is not user
 * intent: `failed`, `needs_auth` and `pending` say nothing about whether the
 * user wants the server, so a transient failure must never edit the config.
 */
export function desiredDisabled(status: McpStatus): boolean | null {
  if (status === "connected") return false
  if (status === "disabled") return true
  return null
}

export interface Write {
  name: string
  disabled: boolean
}

/**
 * The config writes this poll implies.
 *
 * The first poll seeds the baseline and never writes: at startup the runtime
 * state is the config's own state, and a server that failed to boot is not an
 * instruction to disable it. After that, only a status *transition* is a user
 * action.
 */
export function planWrites(
  previous: Map<string, McpStatus> | null,
  servers: McpServerLike[],
): Write[] {
  if (previous === null) return []
  const writes: Write[] = []
  for (const server of servers) {
    const name = typeof server?.name === "string" ? server.name : ""
    if (!name) continue
    const status = statusOf(server)
    if (previous.get(name) === status) continue
    const disabled = desiredDisabled(status)
    if (disabled === null) continue
    writes.push({ name, disabled })
  }
  return writes
}

/**
 * The project's devbot dir, from `.devbot.project.jsonc`'s `devbot_dir`.
 *
 * Generated state (log, locks) lives there rather than in a hardcoded
 * `.agents`, so a project that renamed the vault keeps its runtime files in the
 * directory the CLI actually uses.
 */
export function devbotDirFromConfig(parsed: unknown, fallback = ".agents"): string {
  const value = (parsed as { devbot_dir?: unknown } | undefined)?.devbot_dir
  return typeof value === "string" && value.length > 0 ? value : fallback
}

/** One line for the log: `a=connected, b=disabled`. */
export function summary(map: Map<string, McpStatus>): string {
  return [...map.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([name, status]) => `${name}=${status}`)
    .join(", ")
}

/**
 * The location shape the host hands `setup(ctx)`.
 *
 * `directory` is the session's own directory; `project.canonical` is the
 * project the plugin set was loaded FOR. In a shared-server install — a dev-bot
 * project nested inside another, or several projects served by one
 * `opencode serve` — those differ: `project.canonical` answered the ancestor
 * while the session ran in the nested project, so the sync rewrote the
 * ancestor's `opencode.jsonc` and never touched this project's (audit-01
 * FAIL-2: `loaded for /…/Get-e` in the ancestor's log, a 0-byte log here).
 */
export interface LocationLike {
  directory?: string
  project?: { canonical?: string }
}

/**
 * Root candidates, most authoritative first.
 *
 * The session directory comes first because it is the project the running
 * session actually belongs to; the load-time project (or cwd, on a host that
 * truncates the envelope) is only a signal for a host that omits the directory.
 * Empty values are dropped so an absent key cannot win over a present one.
 */
export function projectRootCandidates(location: LocationLike | undefined, cwd: string): string[] {
  const candidates = [location?.directory, location?.project?.canonical, cwd]
  const seen = new Set<string>()
  const ordered: string[] = []
  for (const candidate of candidates) {
    if (typeof candidate !== "string") continue
    const root = candidate.trim()
    if (!root || seen.has(root)) continue
    seen.add(root)
    ordered.push(root)
  }
  return ordered
}

/**
 * The project the sync may write to, or `""` when there is nothing to sync.
 *
 * Only ONE root is ever considered: the session's own. `project.canonical` is a
 * signal only for a host that omits `directory` — it is never a fallback from a
 * directory that failed validation. Accepting it there is the original bug: in a
 * nested/shared-server install `project.canonical` is the ancestor, so the sync
 * rewrites the ancestor's `opencode.jsonc` while this project goes unsynced
 * (audit-01 FAIL-2, review r4620826453). A session that is not a dev-bot project
 * has nothing to sync, which is not a reason to write somewhere else.
 */
export function resolveProjectRoot(
  location: LocationLike | undefined,
  cwd: string,
  isValid: (dir: string) => boolean,
): string {
  const root = projectRootCandidates(location, cwd)[0] ?? ""
  return root && isValid(root) ? root : ""
}


