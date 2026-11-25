// Default-export `{ id, tui }`; named ones fail.
//
// opencode writes the session title as its own OSC title inside the pane, but
// herdr stops that at the pane boundary, so the label is set from here instead:
// `herdr pane rename` on the pane this TUI runs in.
//
// Every moment the label can go stale has to be covered: the title opencode
// generates shortly AFTER a session is created, a rename at any point in the
// session's life, and a switch to another session.

import { spawn } from "node:child_process"
import { paneTitle, type RouteSource, type SessionInfo, type SessionSource } from "./lib"

const POLL_MS = 500

/** The event slice this plugin reads; `properties.info` carries the session. */
export interface TuiEvent {
  properties?: { info?: SessionInfo; sessionID?: string }
}

/** The slice of the TUI plugin API this plugin uses. */
interface TuiPluginApi {
  state: { session: SessionSource }
  route: RouteSource
  event: { on(type: string, handler: (event: TuiEvent) => void): () => void }
  lifecycle: { onDispose(fn: () => void): void }
}

const tui = async (api: TuiPluginApi) => {
  // HERDR_BIN_PATH is set inside a herdr pane, but a herdr installed on PATH
  // without it is just as usable — the caller wires this plugin for that case.
  const bin = process.env.HERDR_BIN_PATH || "herdr"
  const pane = process.env.HERDR_PANE_ID
  // Outside a herdr pane there is no label to own: the plugin is moot.
  if (process.env.HERDR_ENV !== "1" || !pane) return
  // The session cache arrived in a later 1.x; dev-bot only refuses 2.x, so an
  // older host reaching this factory would otherwise throw on the first sync.
  if (typeof api.state?.session?.get !== "function") return

  // The cache lags the events: opencode assigns a title shortly after creating
  // a session and rewrites it on every rename, so titles are taken from the
  // events and only resolved against the cache as a fallback.
  const known = new Map<string, SessionInfo>()
  const sources: SessionSource = { get: (id) => known.get(id) ?? api.state.session.get(id) }

  const rename = (label: string) =>
    spawn(bin, ["pane", "rename", pane, label], { stdio: "ignore" }).on("error", () => {})

  // undefined until a title is applied, so a manual label set by hand survives
  // both the first sync and a route that has nothing to say.
  let applied: string | undefined

  const sync = () => {
    const title = paneTitle(sources, api.route)
    if (title === applied) return
    applied = title
    // Moving to an untitled session or off the session route drops the claim:
    // keeping the old label would name a session the pane no longer shows.
    rename(title ?? "--clear")
  }

  const remember = (event: TuiEvent) => {
    const info = event?.properties?.info
    if (!info?.id) return
    known.set(info.id, { ...known.get(info.id), ...info })
    sync()
  }

  const forget = (event: TuiEvent) => {
    const id = event?.properties?.sessionID
    if (id) known.delete(id)
    sync()
  }

  const offs = [
    api.event.on("session.created", remember),
    api.event.on("session.updated", remember),
    api.event.on("session.deleted", forget),
  ]
  // opencode emits no route-change event, so a session switch is caught by the
  // poll; a title change does not wait for it.
  const poll = setInterval(sync, POLL_MS)

  api.lifecycle.onDispose(() => {
    clearInterval(poll)
    for (const off of offs) off()
    // The pane outlives the TUI, so drop the claim instead of leaving a label
    // that describes a session nothing is showing any more.
    if (applied !== undefined) rename("--clear")
  })
  sync()
}

export default { id: "herdr-pane-title", tui }
