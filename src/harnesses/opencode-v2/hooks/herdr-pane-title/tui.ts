// TUI part: panes follow the root session's title.
// 2.x ctx: ui.router.current() and data.on(...).

import { spawn } from "node:child_process"
import { paneTitle, type RouteSource, type SessionInfo, type SessionSource } from "./lib"

const POLL_MS = 5000

/** One TUI event as `data.on` delivers it. */
export interface TuiEvent {
  type?: string
  data?: { sessionID?: string; parentID?: string; title?: string }
}

/** The shown route from ui.router.current(). */
export interface TuiRoute {
  type?: string
  sessionID?: string
}

/** The 2.x TUI context slice this plugin uses. */
export interface TuiCtx {
  data?: {
    session?: SessionSource
    on?: (type: string, handler: (event: TuiEvent) => void) => () => void
  }
  ui?: { router?: { current(): TuiRoute } }
}

/** pollMs is a test seam. */
export function setup(ctx: TuiCtx, pollMs = POLL_MS): (() => void) | undefined {
  // HERDR_BIN_PATH is set in a pane, but herdr on
  // PATH is just as usable.
  const bin = process.env.HERDR_BIN_PATH || "herdr"
  const pane = process.env.HERDR_PANE_ID
  // Outside a herdr pane there is no label to own.
  if (process.env.HERDR_ENV !== "1" || !pane) return
  // Without a session cache, an event stream and a
  // router there is nothing to follow.
  const data = ctx?.data
  const router = ctx?.ui?.router
  if (typeof data?.session?.get !== "function" || typeof data.on !== "function") return
  if (typeof router?.current !== "function") return
  const sessions: SessionSource = data.session
  const on = data.on
  const current = router.current.bind(router)

  // Event titles win over the cache; the cache keeps
  // the parentID an event may not carry.
  const known = new Map<string, SessionInfo>()
  const sources: SessionSource = {
    get: (id) => {
      const cached = sessions.get(id)
      const heard = known.get(id)
      if (!cached) return heard
      if (!heard) return cached
      return { ...cached, ...heard }
    },
  }
  const route: RouteSource = {
    get current() {
      const shown = current()
      return shown?.type === "session"
        ? { name: "session", params: { sessionID: shown.sessionID } }
        : { name: shown?.type }
    },
  }

  const rename = (label: string) =>
    spawn(bin, ["pane", "rename", pane, label], { stdio: "ignore" }).on("error", () => {})

  // undefined until applied, so a hand-set label
  // survives the first sync and an idle route.
  let applied: string | undefined

  const sync = () => {
    const title = paneTitle(sources, route)
    if (title === applied) return
    applied = title
    // Off the session route or untitled drops the claim:
    // keeping the old label would name another session.
    rename(title ?? "--clear")
  }

  const remember = (event: TuiEvent) => {
    const payload = event?.data
    if (!payload?.sessionID) return
    const patch: SessionInfo = { id: payload.sessionID }
    if (payload.parentID !== undefined) patch.parentID = payload.parentID
    if (payload.title !== undefined) patch.title = payload.title
    known.set(payload.sessionID, { ...known.get(payload.sessionID), ...patch })
    sync()
  }

  const forget = (event: TuiEvent) => {
    const id = event?.data?.sessionID
    if (id) known.delete(id)
    sync()
  }

  // Titles arrive as session.renamed; the 2.x TUI
  // event union has no session.updated.
  const offs = [
    on("session.created", remember),
    on("session.renamed", remember),
    on("session.deleted", forget),
  ]
  // No route-change event exists: a switch relies on
  // this route-only poll.
  const poll = setInterval(sync, pollMs)
  sync()

  // Disposer: no interval outlives the TUI.
  return () => {
    clearInterval(poll)
    for (const off of offs) off()
    // The pane outlives the TUI: drop the claim, never
    // leave a label for a session it no longer shows.
    if (applied !== undefined) rename("--clear")
  }
}

export default { id: "herdr-pane-title", setup }
