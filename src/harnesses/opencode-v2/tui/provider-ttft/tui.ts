// src/harnesses/opencode-v2/tui/provider-ttft/tui.ts
// Time-to-first-token row for the session sidebar.
//
// Ported from the v1 part (src/harnesses/opencode/provider-ttft) to the 2.3 TUI
// API: `Plugin.define({ id, setup })`, `ctx.ui.slot` for the mount point, and
// `ctx.data.on` for events. The Context block this replaces is the built-in
// plugin `opencode.sidebar.context`; disabling that one is a CLI setting.

import { Plugin } from "@opencode/plugin/tui"
import { createElement, createTextNode, insert, insertNode, setProp } from "@opentui/solid"
import { createSignal } from "solid-js"
import { firstTokenMs, formatTtft, withTtft } from "./lib"

// The order-100 row the Context block used.
const SLOT = "sidebar.content"

// v2 wraps an event payload in `data`; older shapes are tolerated so a renamed
// field degrades to "no value" instead of an exception in the render path.
function payloadOf(event: any): any {
  return event?.data ?? event?.properties ?? event ?? {}
}

export default Plugin.define({
  id: "devbot.provider-ttft",
  setup(ctx) {
    const [bySession, setBySession] = createSignal(new Map<string, number>())

    const stopMessages = ctx.data.on("message.updated", (event: any) => {
      const payload = payloadOf(event)
      const info = payload.info
      const sessionID = payload.sessionID ?? info?.sessionID
      const ms = firstTokenMs(info)
      if (!sessionID || ms === undefined) return
      setBySession((prev) => withTtft(prev, sessionID, ms))
    })

    const unregister = ctx.ui.slot({
      append: SLOT,
      render: ({ sessionID }: { sessionID: string }) => {
        const row = createElement("box")
        setProp(row, "flexDirection", "row")
        setProp(row, "gap", 1)

        const label = createElement("text")
        insertNode(label, createTextNode("TTFT"))
        setProp(label, "fg", ctx.theme.text.base)

        const value = createElement("text")
        insert(value, () => formatTtft(bySession().get(sessionID)))
        setProp(value, "fg", ctx.theme.text.muted)

        insertNode(row, label)
        insertNode(row, value)
        return row
      },
    })

    return () => {
      stopMessages?.()
      unregister?.()
    }
  },
})
