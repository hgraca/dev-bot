// The 2.x TUI host double, typed against the pinned
// host package so the fake cannot drift.
//
// @opencode/client and @opencode/plugin are a pinned
// pair (2.4.1); move them together.

import type { OpenCodeEvent } from "@opencode/client"
import type { Plugin } from "@opencode/plugin/tui"
import type { SessionInfo } from "./lib"
import type { TuiCtx } from "./tui"

type Route = ReturnType<Plugin.Context["ui"]["router"]["current"]>
type Mutable<T> = { -readonly [K in keyof T]: T[K] }
type MutableRoute = Mutable<Route>
type On = Plugin.Context["data"]["on"]
type Emitted = "session.created" | "session.renamed" | "session.deleted"
type EventMap = { [Type in OpenCodeEvent["type"]]: Extract<OpenCodeEvent, { type: Type }> }
type Payload<Type extends Emitted> = EventMap[Type]["data"]

export type { MutableRoute }

export const route = (sessionID?: string): MutableRoute =>
  sessionID === undefined ? { type: "home" } : { type: "session", sessionID }

export function host(records: SessionInfo[], shown: MutableRoute = route("root")) {
  const sessions = new Map(records.map((s) => [s.id, s]))
  const handlers = new Map<string, Array<(event: unknown) => void>>()

  const on: On = (type, handler) => {
    const list = handlers.get(type) ?? []
    list.push(handler as unknown as (event: unknown) => void)
    handlers.set(type, list)
    return () => handlers.set(type, (handlers.get(type) ?? []).filter((h) => h !== handler))
  }

  const ctx: TuiCtx = {
    data: { session: { get: (id) => sessions.get(id) }, on },
    ui: { router: { current: () => shown } },
  }

  return {
    ctx,
    emit<Type extends Emitted>(type: Type, data: Payload<Type>) {
      // A delete drops the cache record too, the way the
      // host's store does.
      if (type === "session.deleted") {
        const id = (data as Payload<"session.deleted">).sessionID
        if (id) sessions.delete(id)
      }
      for (const handler of handlers.get(type) ?? []) handler({ type, data })
    },
  }
}
