// =============================================================================
// src/harnesses/opencode/herdr-pane-title/lib.ts
// The pure logic behind dev-bot's herdr pane-title TUI plugin, kept out of the
// wiring so a fake host can exercise it.
//
// herdr has no configuration that puts a pane's terminal title in its border —
// the border shows a manual pane label or, when the label is unset, the agent
// name. So the label is owned here, and the only question this file answers is
// which title it should carry.
// =============================================================================

/** The slice of a session record this plugin reads. */
export interface SessionInfo {
  id: string
  title?: string
  parentID?: string
}

/** The slice of `api.state.session` this plugin needs. */
export interface SessionSource {
  get(id: string): SessionInfo | undefined
}

/** The slice of `api.route` this plugin needs. */
export interface RouteSource {
  readonly current?: { name?: string; params?: Record<string, unknown> }
}

/**
 * The root of a session chain. A pane showing a subagent keeps its root
 * session's label, so the walk follows parentID up and stops at the first
 * session without one. `seen` guards a malformed cycle rather than hanging.
 */
export function rootSession(sessions: SessionSource, id: unknown): SessionInfo | undefined {
  const seen = new Set<string>()
  while (typeof id === "string" && !seen.has(id)) {
    seen.add(id)
    const session = sessions.get(id)
    if (!session) return undefined
    if (!session.parentID) return session
    id = session.parentID
  }
  return undefined
}

/**
 * The title the pane should show, or undefined when it should keep whatever
 * label it has — not on a session route, the session is not cached yet, or it
 * has no title. An untitled session carries "" rather than no title at all, so
 * emptiness is folded here and the wiring has one rule to apply.
 */
export function paneTitle(sessions: SessionSource, route: RouteSource): string | undefined {
  const current = route.current
  if (current?.name !== "session") return undefined
  const id = current.params?.sessionID
  if (typeof id !== "string") return undefined
  return rootSession(sessions, id)?.title || undefined
}
