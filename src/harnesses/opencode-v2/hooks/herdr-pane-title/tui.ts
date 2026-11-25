// src/harnesses/opencode-v2/hooks/herdr-pane-title/tui.ts
// TUI part: keeps the herdr pane border label on the ROOT session's title.
//
// V2 validates the `./tui` default export as `{ id, setup(ctx) }` and rejects
// anything else with "Invalid V2 TUI plugin module", which is a failed plugin at
// startup. 2.3 also changed the surface the ctx exposes: events arrive as an
// async stream (`subscribe({ signal })`, payload under `data`) rather than v1's
// `event.on(type, handler)` with `properties`, and a TUI plugin cleans up by
// RETURNING a disposer instead of registering one.

import { spawn } from "node:child_process"
import { eventPayload } from "../../on-hooks-utils"
import { paneTitle, type RouteSource, type SessionInfo, type SessionSource } from "./lib"

const POLL_MS = 500

/** The ctx surface this plugin uses, every member optional by design. */
export interface TuiCtx {
  state?: { session?: SessionSource }
  route?: RouteSource
  event?: { subscribe(options: { signal: AbortSignal }): AsyncIterable<unknown> }
}

export function setup(ctx: TuiCtx): (() => void) | undefined {
  // HERDR_BIN_PATH is set inside a herdr pane, but a herdr installed on PATH
  // without it is just as usable.
  const bin = process.env.HERDR_BIN_PATH || "herdr"
  const pane = process.env.HERDR_PANE_ID
  // Outside a herdr pane there is no label to own: the plugin is moot.
  if (process.env.HERDR_ENV !== "1" || !pane) return
  // Without a session cache and a route there is nothing to follow.
  if (typeof ctx?.state?.session?.get !== "function" || !ctx.route) return

  const sessions = ctx.state.session
  const route = ctx.route

  // The cache lags the events: opencode assigns a title shortly after creating
  // a session and rewrites it on every rename, so titles are taken from the
  // events and only resolved against the cache as a fallback.
  const known = new Map<string, SessionInfo>()
  const sources: SessionSource = { get: (id) => known.get(id) ?? sessions.get(id) }

  const rename = (label: string) =>
    spawn(bin, ["pane", "rename", pane, label], { stdio: "ignore" }).on("error", () => {})

  // undefined until a title is applied, so a manual label set by hand survives
  // both the first sync and a route that has nothing to say.
  let applied: string | undefined

  const sync = () => {
    const title = paneTitle(sources, route)
    if (title === applied) return
    applied = title
    // Moving to an untitled session or off the session route drops the claim:
    // keeping the old label would name a session the pane no longer shows.
    rename(title ?? "--clear")
  }

  const controller = new AbortController()
  if (typeof ctx.event?.subscribe === "function") {
    void (async () => {
      try {
        for await (const event of ctx.event!.subscribe({ signal: controller.signal })) {
          const type = (event as { type?: string } | undefined)?.type
          const payload = eventPayload(event)
          if (type === "session.deleted") {
            const id = payload?.sessionID
            if (typeof id === "string") known.delete(id)
          } else if (type === "session.created" || type === "session.updated") {
            const info = payload?.info as SessionInfo | undefined
            if (!info?.id) continue
            known.set(info.id, { ...known.get(info.id), ...info })
          } else {
            continue
          }
          sync()
        }
      } catch {
        // An abort is the normal unload path.
      }
    })()
  }

  // opencode emits no route-change event, so a session switch is caught by the
  // poll; a title change does not wait for it.
  const poll = setInterval(sync, POLL_MS)
  sync()

  // The returned disposer is the v2 cleanup contract, so the interval can never
  // outlive the TUI it belongs to.
  return () => {
    controller.abort()
    clearInterval(poll)
    // The pane outlives the TUI, so drop the claim instead of leaving a label
    // that describes a session nothing is showing any more.
    if (applied !== undefined) rename("--clear")
  }
}

export default { id: "herdr-pane-title", setup }
